use std::{path::{PathBuf, Path}, fs::{File, self, Metadata}, io::{BufRead, BufReader, self}};

use clap::{Arg, ArgAction, Command};
use regex::Regex;

#[derive(Clone, Copy)]
enum CleanupMode {
    CleanupBase,
    CleanupUser
}

#[derive(Debug)]
struct Pattern {
    pattern: regex::Regex
}
impl Pattern {
    pub fn from_str(pattern_str: &str) -> Self {
        let mut pattern_regex = pattern_str.to_owned();

        pattern_regex = pattern_regex
            .replace("/**/", "/.*/")
            .replace("/*/", "/[^/]+/");
        if pattern_regex.ends_with("/*") {
            pattern_regex.replace_range(pattern_regex.len()-2.., "/[^/]+");
        }
        pattern_regex = pattern_regex.replace("*", "[^/]*");
        if pattern_regex.contains("*") || pattern_regex.ends_with("/") {
            panic!("Invalid Pattern: {}", pattern_str);
        }

        pattern_regex = format!("^{}$", pattern_regex);
        Self {
            pattern: Regex::new(&pattern_regex).expect(&format!("Failed to parse pattern: {}", pattern_regex))
        }
    }
    pub fn matches(&self, path: &Path) -> bool {
        self.pattern.is_match(path.to_str().unwrap())
    }
}

enum PatternAction {
    Delete,
    DescendAndDeleteIfEmpty,
    DescendAndKeep,
    Keep
}

#[derive(Debug)]
struct Patterns {
    base_always: Vec<Pattern>,
    base_initially: Vec<Pattern>
}
impl Patterns {
    fn match_any(patterns: &Vec<Pattern>, path: &Path) -> bool {
        for pattern in patterns {
            if pattern.matches(path) { return true; }
        }
        false
    }

    pub fn get_action(&self, mode: CleanupMode, root_path: &Path, item: &Path, item_meta: &Metadata) -> PatternAction {
        let rel_path = item.strip_prefix(root_path).expect("Path error! Descent path has to be child in root");
        let is_dir = item_meta.is_dir();
        match mode {
            CleanupMode::CleanupBase => {
                // patterns describe what to keep in base
                if Patterns::match_any(&self.base_always, rel_path) { return PatternAction::Keep; }
                if Patterns::match_any(&self.base_initially, rel_path) { return PatternAction::Keep; }
                if is_dir {
                    return PatternAction::DescendAndDeleteIfEmpty;
                } else {
                    return PatternAction::Delete;
                }
            },
            CleanupMode::CleanupUser => {
                // base always patterns describe what is always provided by base, so has to be deleted in user
                if Patterns::match_any(&self.base_always, rel_path) { return PatternAction::Delete; }
                if is_dir {
                    // continue on and see whether there is anything in the folder that is marked base-always
                    return PatternAction::DescendAndKeep;
                } else {
                    return PatternAction::Keep; // keep everything else in user dir
                }
            }
        }
    }
}




fn parse_rules(keep_file: &Path) -> Patterns {
    let file = File::open(keep_file).expect("Failed to open keep file!");
    let reader = BufReader::new(file);

    let mut base_always = Vec::new();
    let mut base_initially = Vec::new();

    // default patterns
    base_always.push(Pattern::from_str(".keep"));

    for line in reader.lines() {
        let line = line.expect("Failed to read keep file");
        if line.starts_with("b ") {
            base_always.push(Pattern::from_str(&line[2..]));
        } else if line.starts_with("bi ") {
            base_initially.push(Pattern::from_str(&line[3..]));
        }
    }

    Patterns { base_always, base_initially }
}

fn apply_keep(mode: CleanupMode, dryrun: bool, patterns: &Patterns, root_path: PathBuf) {
    if !root_path.is_dir() {
        panic!("Given folder either does not exist or is actually a file.");
    }

    fn traverse(mode: CleanupMode, dryrun: bool, patterns: &Patterns, root_path: &Path, cur_path: PathBuf) -> io::Result<bool> {
        let mut is_empty = true;

        for child in fs::read_dir(&cur_path)?.filter_map(|f| f.ok()) {
            let metadata = child.metadata()?;
            match patterns.get_action(mode, root_path, &child.path(), &metadata) {
                PatternAction::Delete => {
                    if metadata.is_dir() {
                        println!("[DELETE] Folder {}", child.path().display());
                        if !dryrun { fs::remove_dir_all(&child.path())?; }
                    } else {
                        println!("[DELETE] File {}", child.path().display());
                        if !dryrun { fs::remove_file(&child.path())?; }
                    }
                },
                PatternAction::DescendAndDeleteIfEmpty => {
                    let child_empty = traverse(mode, dryrun, patterns, root_path, child.path())?;
                    if child_empty {
                        println!("[DELETE] Empty Folder {}", child.path().display());
                        if !dryrun { fs::remove_dir(&child.path())?; }
                    } else {
                        is_empty = false;
                    }
                },
                PatternAction::DescendAndKeep => {
                    traverse(mode, dryrun, patterns, root_path, child.path())?;
                    is_empty = false;
                },
                PatternAction::Keep => {
                    is_empty = false;
                },
            }
        }

        Ok(is_empty)
    }

    let _ = traverse(mode, dryrun, patterns, root_path.as_path(), root_path.clone());
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
    println!("{:?}", matches);

    let mode = matches.get_one::<String>("mode").unwrap();
    let keep_rules_file = matches.get_one::<PathBuf>("keepRulesFile").unwrap();
    let folder = matches.get_one::<PathBuf>("folder").unwrap();
    let dryrun = matches.get_flag("dryrun");

    let mode = match mode.as_str() {
        "base" => CleanupMode::CleanupBase,
        "user" => CleanupMode::CleanupUser,
        _ => unreachable!()
    };
    let patterns = parse_rules(&keep_rules_file);
    apply_keep(mode, dryrun, &patterns, folder.clone());
}
