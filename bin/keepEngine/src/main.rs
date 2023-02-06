mod decisiongraph;

use std::{path::{PathBuf, Path}, fs::{File, self}, io::{BufRead, BufReader, self}};

use anyhow::Result;
use clap::{ValueEnum, Parser};
use decisiongraph::DecisionGraph;


use crate::decisiongraph::FileAction;

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum CleanupMode {
    Base,
    User
}

fn parse_rules(keep_file: &Path) -> Result<DecisionGraph> {
    let file = File::open(keep_file).expect("Failed to open keep file!");
    let reader = BufReader::new(file);

    let mut decision_graph = DecisionGraph::new();

    for line in reader.lines() {
        let line = line.expect("Failed to read keep file");
        if !line.starts_with("#") && line.trim() != "" {
            decision_graph.add_rule_from_str(&line)?;
        }
    }

    // enforced default rules
    decision_graph.add_rule_from_str("base:keep user:delete .keep")?;

    Ok(decision_graph)
}

fn apply_keep(args: &CliArgs, decision_graph: &DecisionGraph) {
    if !args.folder.is_dir() {
        panic!("Given folder either does not exist or is actually a file.");
    }

    // depth first
    fn traverse(args: &CliArgs, decision_graph: &DecisionGraph, cur_path: PathBuf) -> io::Result<bool> {
        let mut is_empty = true;

        for child in fs::read_dir(&cur_path)?.filter_map(|f| f.ok()) {
            let child_path = child.path();
            let rel_path = child_path.strip_prefix(&args.folder).unwrap();

            let decision = decision_graph.get_action(&rel_path);
            let descend = decision.descend;
            let action = match args.mode {
                CleanupMode::Base => decision.actions.base,
                CleanupMode::User => decision.actions.user,
            };

            if child.file_type()?.is_dir() {
                if descend {
                    let child_empty = traverse(args, decision_graph, child.path())?;
                    is_empty &= child_empty;
                    if child_empty && matches!(action, FileAction::Delete) {
                        if args.verbose { println!("[DELETE] Folder: {}", child.path().display()); }
                        if !args.dryrun { let _ = fs::remove_dir(child.path()); }
                    }
                } else {
                    if matches!(action, FileAction::Delete) {
                        if args.verbose { println!("[DELETE] Folder recursively: {}", child.path().display()); }
                        if !args.dryrun { let _ = fs::remove_dir_all(child.path()); }
                    } else {
                        is_empty = false;
                    }
                }
            } else {
                if matches!(action, FileAction::Delete) {
                    if args.verbose { println!("[DELETE] File: {}", child.path().display()); }
                    if !args.dryrun { let _ = fs::remove_file(child.path()); }
                } else {
                    is_empty = false;
                }
            }
        }
        Ok(is_empty)
    }

    let _ = traverse(args, decision_graph, args.folder.clone());
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
