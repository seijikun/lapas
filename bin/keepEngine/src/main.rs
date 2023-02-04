use std::{path::{PathBuf, Path}, fs::{File, self}, io::{BufRead, BufReader, self}, str::FromStr};

use anyhow::{anyhow, Result};
use clap::{ValueEnum, Parser};
use regex::Regex;

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum CleanupMode {
    Base,
    User
}

#[derive(Clone, Copy, Debug)]
enum FileAction {
    Delete,
    Keep
}
impl FromStr for FileAction {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "keep" => Ok(FileAction::Keep),
            "delete" => Ok(FileAction::Delete),
            _ => Err(anyhow!("Invalid rule action"))
        }
    }
}

#[derive(Debug)]
struct Rule { pattern: Regex, base_action: FileAction, user_action: FileAction }
impl Rule {
    pub fn regex_from_pattern_str(pattern_str: &str) -> Result<Regex> {
        if pattern_str.ends_with("/") {
            return Err(anyhow!("Invalid pattern! Rules followed with a slash won't match anything: '{}'", pattern_str));
        }

        let mut pattern_regex = pattern_str.to_owned()
            .replace("/**/", "/.+/")
            .replace("/*/", "/[^/]+/");
        if pattern_regex.ends_with("/**") {
            pattern_regex.replace_range(pattern_regex.len()-2.., ".+");
        }
        if pattern_regex.starts_with("**/") || pattern_regex == "**" {
            pattern_regex.replace_range(0..2, ".+");
        }

        if pattern_regex.ends_with("/*") {
            pattern_regex.replace_range(pattern_regex.len()-1.., "[^/]+");
        }
        if pattern_regex.starts_with("*/") || pattern_regex == "*" {
            pattern_regex.replace_range(0..1, "[^/]+");
        }

        if pattern_regex.contains("**") {
            return Err(anyhow!("Invalid Pattern. Double-stars are only allowed in isolation between path separators: {}", pattern_str));
        }

        pattern_regex = pattern_regex.replace("*", "[^/]*");

        pattern_regex = format!("^{}$", pattern_regex);
        Ok(Regex::new(&pattern_regex)?)
    }

    pub fn matches(&self, path: &Path) -> bool {
        self.pattern.is_match(path.to_str().unwrap())
    }
}

#[derive(Debug)]
struct Rules {
    rules: Vec<Rule>
}
impl Rules {
    pub fn new() -> Self {
        Self { rules: vec![] }
    }
    pub fn add_rule_from_str(&mut self, rule_line: &str) -> Result<()> {
        let rule_segments: Vec<_> = rule_line.splitn(3, ' ').collect();
        assert!(rule_segments.len() == 3, "Invalid Rule: {}", rule_line);

        let base_action_str = if rule_segments[0].starts_with("base:") { rule_segments[0] } else { rule_segments[1] };
        let user_action_str = if rule_segments[0].starts_with("user:") { rule_segments[0] } else { rule_segments[1] };
        assert!(base_action_str.starts_with("base:") && user_action_str.starts_with("user:"), "Invalid Rule: {}", rule_line);
        let base_action = base_action_str[5..].parse::<FileAction>()?;
        let user_action = user_action_str[5..].parse::<FileAction>()?;

        let file_pattern = Rule::regex_from_pattern_str(rule_segments[2])?;
        // So that a normal rule can also affect folders recursively, we simply create it by applying the
        // pattern with a programatically appended allmatch /**
        let folder_pattern = Rule::regex_from_pattern_str(&format!("{}/**", rule_segments[2]))?;

        self.rules.push(Rule { pattern: file_pattern, base_action, user_action });
        self.rules.push(Rule { pattern: folder_pattern, base_action, user_action });

        Ok(())
    }

    pub fn get_action(&self, mode: CleanupMode, root_path: &Path, item: &Path) -> FileAction {
        let mut action = FileAction::Keep;

        for rule in &self.rules {
            let rel_path = item.strip_prefix(root_path).expect("Path error! Descent path has to be child in root");
            if rule.matches(rel_path) {
                action = match mode {
                    CleanupMode::Base => rule.base_action,
                    CleanupMode::User => rule.user_action,
                };
            }
        }

        action
    }
}

fn parse_rules(keep_file: &Path) -> Result<Rules> {
    let file = File::open(keep_file).expect("Failed to open keep file!");
    let reader = BufReader::new(file);

    let mut rules = Rules::new();

    for line in reader.lines() {
        let line = line.expect("Failed to read keep file");
        if !line.starts_with("#") && line.trim() != "" {
            rules.add_rule_from_str(&line)?;
        }
    }

    // enforced default rules
    rules.add_rule_from_str("base:keep user:delete .keep")?;

    Ok(rules)
}

fn apply_keep(args: &CliArgs, rules: &Rules) {
    if !args.folder.is_dir() {
        panic!("Given folder either does not exist or is actually a file.");
    }

    // depth first
    fn traverse(args: &CliArgs, rules: &Rules, cur_path: PathBuf) -> io::Result<bool> {
        let mut is_empty = true;

        for child in fs::read_dir(&cur_path)?.filter_map(|f| f.ok()) {
            let metadata = child.metadata()?;
            let action = rules.get_action(args.mode, &args.folder, &child.path());
            if metadata.is_dir() {
                let child_empty = traverse(args, rules, child.path())?;
                is_empty &= child_empty;
                if child_empty && matches!(action, FileAction::Delete) {
                    if args.verbose { println!("[DELETE] Folder {}", child.path().display()); }
                    if !args.dryrun { let _ = fs::remove_dir(child.path()); }
                }
            } else {
                if matches!(action, FileAction::Delete) {
                    if args.verbose { println!("[DELETE] File {}", child.path().display()); }
                    if !args.dryrun { let _ = fs::remove_file(child.path()); }
                } else {
                    is_empty = false;
                }
            }
        }
        Ok(is_empty)
    }

    let _ = traverse(args, rules, args.folder.clone());
}

#[derive(Debug, Parser)]
#[command(name = "keepEngine")]
#[command(author, version, about)]
struct CliArgs {
    /// Mode of operation. Either applies the keep rules to
    #[arg(value_name = "MODE", value_enum)]
    mode: CleanupMode,
    /// Path to the .keep file that should be applied
    #[arg(value_name = "KEEP_RULES_FILE")]
    keep_file_path: PathBuf,
    /// Folder that the rules should be applied to (either base user or normal user home)
    #[arg(value_name = "FOLDER")]
    folder: PathBuf,

    /// If this flag is set, the engine will run in test-mode
    #[arg(long, default_value_t = false)]
    dryrun: bool,
    /// If this flag is set, every delete operation will be logged to the console
    #[arg(long, default_value_t = false)]
    verbose: bool
}

fn main() {
    let args = CliArgs::parse();
    let rules = parse_rules(&args.keep_file_path).unwrap();
    apply_keep(&args, &rules);
}
