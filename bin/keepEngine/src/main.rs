use std::{path::{PathBuf, Path}, fs::{File, self}, io::{BufRead, BufReader, self}, str::FromStr};

use anyhow::{anyhow, Result};
use clap::{Arg, ArgAction, Command};
use regex::Regex;

#[derive(Clone, Copy)]
enum CleanupMode {
    CleanupBase,
    CleanupUser
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
                    CleanupMode::CleanupBase => rule.base_action,
                    CleanupMode::CleanupUser => rule.user_action,
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

fn apply_keep(mode: CleanupMode, dryrun: bool, rules: &Rules, root_path: PathBuf) {
    if !root_path.is_dir() {
        panic!("Given folder either does not exist or is actually a file.");
    }

    // depth first
    fn traverse(mode: CleanupMode, dryrun: bool, rules: &Rules, root_path: &Path, cur_path: PathBuf) -> io::Result<bool> {
        let mut is_empty = true;

        for child in fs::read_dir(&cur_path)?.filter_map(|f| f.ok()) {
            let metadata = child.metadata()?;
            let action = rules.get_action(mode, root_path, &child.path());
            if metadata.is_dir() {
                let child_empty = traverse(mode, dryrun, rules, root_path, child.path())?;
                is_empty &= child_empty;
                if child_empty && matches!(action, FileAction::Delete) {
                    println!("[DELETE] Folder {}", child.path().display());
                    if !dryrun { let _ = fs::remove_dir(child.path()); }
                }
            } else {
                if matches!(action, FileAction::Delete) {
                    println!("[DELETE] File {}", child.path().display());
                    if !dryrun { let _ = fs::remove_file(child.path()); }
                } else {
                    is_empty = false;
                }
            }
        }
        Ok(is_empty)
    }

    let _ = traverse(mode, dryrun, rules, root_path.as_path(), root_path.clone());
}

fn main() {
    let matches = Command::new("keepEngine")
        .about("Keep Engine parses the base user\'s .keep file and deletes files accordingly")
        .version("0.1")
        .author("Markus Ebner")
        .arg(
            Arg::new("mode")
                .required(true)
                .help("Mode of operation. Either applies the keep rules to")
                .action(ArgAction::Set)
                .value_parser(["base", "user"])
        )
        .arg(
            Arg::new("keepRulesFile")
                .help("Path to the .keep file that should be applied")
                .required(true)
                .value_parser(clap::value_parser!(PathBuf))
                .action(ArgAction::Set)
        )
        .arg(
            Arg::new("folder")
            .help("Folder that the rules should be applied to (either base user or normal user home)")
            .required(true)
            .value_parser(clap::value_parser!(PathBuf))
            .action(ArgAction::Set)
        )
        .arg(
            Arg::new("dryrun")
                .long("dryrun")
                .help("If this flag is set, the engine will run in test-mode")
                .action(ArgAction::SetTrue)
        )
        .get_matches();

    let mode = matches.get_one::<String>("mode").unwrap();
    let keep_rules_file = matches.get_one::<PathBuf>("keepRulesFile").unwrap();
    let folder = matches.get_one::<PathBuf>("folder").unwrap();
    let dryrun = matches.get_flag("dryrun");

    let mode = match mode.as_str() {
        "base" => CleanupMode::CleanupBase,
        "user" => CleanupMode::CleanupUser,
        _ => unreachable!()
    };
    let rules = parse_rules(&keep_rules_file).unwrap();
    apply_keep(mode, dryrun, &rules, folder.clone());
}
