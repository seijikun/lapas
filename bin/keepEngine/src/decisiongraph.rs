use anyhow::{anyhow, Result};
use regex::Regex;
use std::{fmt::Write as _, fs::File, io::Write as _, path::Path, str::FromStr};

#[derive(Clone, Copy, Debug)]
pub enum FileAction {
    Delete,
    Keep,
}
impl FromStr for FileAction {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "keep" => Ok(FileAction::Keep),
            "delete" => Ok(FileAction::Delete),
            _ => Err(anyhow!("Invalid rule action")),
        }
    }
}

#[derive(Clone, Copy)]
pub struct Actions {
    pub base: FileAction,
    pub user: FileAction,
}
pub struct ActionResult {
    pub actions: Actions,
    pub descend: bool,
}

trait DecisionNodeImpl: AsDecisionNodeImpl {
    fn children(&self) -> &Vec<Box<dyn DecisionNode>>;
    fn children_mut(&mut self) -> &mut Vec<Box<dyn DecisionNode>>;
}
trait AsDecisionNodeImpl {
    #[allow(unused)]
    fn as_impl(&self) -> &dyn DecisionNodeImpl;
    fn as_impl_mut(&mut self) -> &mut dyn DecisionNodeImpl;
}
trait DecisionNode: DecisionNodeImpl {
    /// Access to the raw pattern that produced this child
    fn pattern(&self) -> &str;
    #[allow(unused)]
    fn actions(&self) -> &Option<Actions>;

    fn get_action(&self, segments: &[&str], result: &mut ActionResult);

    #[allow(unused)]
    fn write_dot_to_str(&self, output: &mut String, parent_id: &str) -> Result<()> {
        let id = uuid::Uuid::new_v4().to_string();
        let action_str = match self.actions() {
            Some(actions) => format!("base: {:?}, user: {:?}", actions.base, actions.user),
            None => "".to_owned(),
        };
        output.write_fmt(format_args!(
            "\"{}\" [label=\"<f0> {}| <f1> {}\", shape=\"record\"];\n",
            id,
            self.pattern(),
            action_str
        ))?;
        output.write_fmt(format_args!("\"{}\" -> \"{}\";\n", parent_id, id))?;
        for child in self.children() {
            child.write_dot_to_str(output, &id)?;
        }
        Ok(())
    }
}

// auto-trait implementation that allows upcasting from DecisionNode to DecisionNodeImpl
impl<T: DecisionNodeImpl> AsDecisionNodeImpl for T {
    fn as_impl(&self) -> &dyn DecisionNodeImpl {
        self
    }
    fn as_impl_mut(&mut self) -> &mut dyn DecisionNodeImpl {
        self
    }
}

/// Node for the multi-segment all-match pattern: "**"
struct MultiSegmentNode {
    actions: Option<Actions>,
    children: Vec<Box<dyn DecisionNode>>,
}
impl MultiSegmentNode {
    pub fn new(actions: Option<Actions>) -> Self {
        Self {
            actions,
            children: vec![],
        }
    }
}
impl DecisionNodeImpl for MultiSegmentNode {
    fn children(&self) -> &Vec<Box<dyn DecisionNode>> {
        &self.children
    }
    fn children_mut(&mut self) -> &mut Vec<Box<dyn DecisionNode>> {
        &mut self.children
    }
}
impl DecisionNode for MultiSegmentNode {
    fn pattern(&self) -> &str {
        "**"
    }
    fn actions(&self) -> &Option<Actions> {
        &self.actions
    }

    fn get_action(&self, segments: &[&str], result: &mut ActionResult) {
        if let Some(actions) = self.actions {
            result.actions = actions;
        }
        if self.children.len() > 0 {
            // tell recursor to look forward, we haven't reached end of this pattern hierarchy yet
            if segments.len() == 1 {
                result.descend = true;
            }
            // try by consuming [1..n - 1] segments (leave at least 1 for the following node)
            for i in 1..self.children.len() - 1 {
                for child in &self.children {
                    child.get_action(&segments[i..], result);
                }
            }
        }
    }
}

/// Node for single-segment patterns like:
/// - *.log
/// - *
/// - .config
struct SingleSegmentNode {
    pattern: String,
    regex_pattern: Regex,
    actions: Option<Actions>,
    children: Vec<Box<dyn DecisionNode>>,
}
impl SingleSegmentNode {
    pub fn from_pattern(pattern: String, actions: Option<Actions>) -> Result<Self> {
        // The only pattern we support is a single glob star. We convert the segment to a
        // regex. In order to do this safely, we need to regex-escape the pattern string. But that
        // would also escape the glob star.
        let regex_pattern_str = match pattern.as_str() {
            "*" => "[^/]+".to_owned(),
            _ => regex::escape(&pattern.replace("*", "@KEEPENGINEGLOBSTAR@"))
                .replace("@KEEPENGINEGLOBSTAR@", "[^/]*"),
        };
        let regex_pattern_str = format!("^{}$", regex_pattern_str);
        let regex_pattern = Regex::new(&regex_pattern_str)?;

        Ok(Self {
            pattern,
            regex_pattern,
            actions,
            children: vec![],
        })
    }
}
impl DecisionNodeImpl for SingleSegmentNode {
    fn children(&self) -> &Vec<Box<dyn DecisionNode>> {
        &self.children
    }
    fn children_mut(&mut self) -> &mut Vec<Box<dyn DecisionNode>> {
        &mut self.children
    }
}
impl DecisionNode for SingleSegmentNode {
    fn pattern(&self) -> &str {
        &self.pattern
    }
    fn actions(&self) -> &Option<Actions> {
        &self.actions
    }

    fn get_action(&self, segments: &[&str], result: &mut ActionResult) {
        let matches = self.regex_pattern.is_match(segments[0]);
        if !matches {
            return;
        }
        if let Some(actions) = self.actions {
            result.actions = actions;
        }
        if segments.len() == 1 {
            // tell recursor to look forward, we haven't reached end of this pattern hierarchy yet
            if self.children.len() > 0 {
                result.descend = true;
            }
        } else {
            // continue in pattern hierarchy
            for child in &self.children {
                child.get_action(&segments[1..], result);
            }
        }
    }
}

pub struct DecisionGraph {
    children: Vec<Box<dyn DecisionNode>>,
}
impl DecisionNodeImpl for DecisionGraph {
    fn children(&self) -> &Vec<Box<dyn DecisionNode>> {
        &self.children
    }
    fn children_mut(&mut self) -> &mut Vec<Box<dyn DecisionNode>> {
        &mut self.children
    }
}
impl DecisionGraph {
    pub fn new() -> Self {
        Self {
            children: vec![Box::new(
                SingleSegmentNode::from_pattern(
                    "**".to_owned(),
                    Some(Actions {
                        base: FileAction::Delete,
                        user: FileAction::Keep,
                    }),
                )
                .unwrap(),
            )],
        }
    }
    pub fn add_rule_from_str(&mut self, rule_line: &str) -> Result<()> {
        let rule_segments: Vec<_> = rule_line.splitn(3, ' ').collect();
        assert!(rule_segments.len() == 3, "Invalid Rule: {}", rule_line);

        let base_action_str = if rule_segments[0].starts_with("base:") {
            rule_segments[0]
        } else {
            rule_segments[1]
        };
        let user_action_str = if rule_segments[0].starts_with("user:") {
            rule_segments[0]
        } else {
            rule_segments[1]
        };
        assert!(
            base_action_str.starts_with("base:") && user_action_str.starts_with("user:"),
            "Invalid Rule: {}",
            rule_line
        );
        let base_action = base_action_str[5..].parse::<FileAction>()?;
        let user_action = user_action_str[5..].parse::<FileAction>()?;

        let rule_segments: Vec<_> = rule_segments[2].split('/').collect();
        assert!(
            rule_segments.len() >= 1,
            "Invalid Rule: Pattern has no segments"
        );
        self.add_rule(
            &rule_segments,
            Actions {
                base: base_action,
                user: user_action,
            },
        )?;

        Ok(())
    }

    pub fn get_action(&self, path: &Path) -> ActionResult {
        let path_segments: Vec<_> = path.to_str().unwrap().split('/').collect();
        let mut result = ActionResult {
            actions: Actions {
                base: FileAction::Keep,
                user: FileAction::Keep,
            },
            descend: false,
        };
        for child in &self.children {
            child.get_action(&path_segments, &mut result);
        }
        result
    }

    fn node_from_segment_pattern(
        segment_pattern: &str,
        actions: Option<Actions>,
    ) -> Result<Box<dyn DecisionNode>> {
        if segment_pattern == "**" {
            Ok(Box::new(MultiSegmentNode::new(actions)))
        } else {
            if segment_pattern.contains("**") {
                return Err(anyhow!("Invalid Pattern. Double-stars are only allowed in isolation between path separators: {}", segment_pattern));
            }
            Ok(Box::new(SingleSegmentNode::from_pattern(
                segment_pattern.to_owned(),
                actions,
            )?))
        }
    }

    fn add_rule(&mut self, segments: &[&str], actions: Actions) -> Result<()> {
        fn traverse_add(
            node: &mut dyn DecisionNodeImpl,
            segments: &[&str],
            actions: &Actions,
        ) -> Result<()> {
            let next_node_actions = if segments.len() != 1 {
                None
            } else {
                Some(actions.clone())
            };

            if segments.len() == 1 {
                // If we are at the last segment and the node has children that perfectly match our
                // pattern, we replace them. We would have higher priority anyway
                node.children_mut().retain(|n| n.pattern() != segments[0]);
            }
            // to keep the absolute ordering of rules intact, we must only append to the last child (if it matches our segment)
            let last_child = node.children().last();
            if segments.len() == 1
                || last_child.is_none()
                || last_child.unwrap().pattern() != segments[0]
            {
                // no matching segment for the next pattern segment -> add
                node.children_mut()
                    .push(DecisionGraph::node_from_segment_pattern(
                        segments[0],
                        next_node_actions,
                    )?);
            }
            // descend
            if segments.len() > 1 {
                // recursion
                for child in node.children_mut() {
                    if child.pattern() == segments[0] {
                        traverse_add(child.as_impl_mut(), &segments[1..], actions)?;
                    }
                }
            }
            Ok(())
        }

        traverse_add(self, segments, &actions)
    }

    #[allow(unused)]
    pub fn write_dot_to_file(&self, path: &str) -> Result<()> {
        let mut output = String::new();

        output.write_str("digraph patterns {\n")?;
        output.write_str("node [shape=box];\n")?;
        output.write_str("graph [ rankdir=\"LR\" ];\n")?;
        output.write_str("\"root\" [shape=\"diamond\"];\n")?;
        for child in &self.children {
            child.write_dot_to_str(&mut output, "root")?;
        }
        output.write_str("}")?;

        let mut vis_file = File::create(path)?;
        vis_file.write_all(output.as_bytes())?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use crate::decisiongraph::FileAction;

    use super::DecisionGraph;

    macro_rules! graph_assert {
        ($graph:ident, $path:literal, $descend:literal, $base_action:ident, $user_action:ident) => {
            let result = $graph.get_action(&PathBuf::from($path));
            assert_eq!(result.descend, $descend);
            assert!(matches!(result.actions.base, FileAction::$base_action));
            assert!(matches!(result.actions.user, FileAction::$user_action));
        };
    }

    fn construct_typical_lapas_graph() -> DecisionGraph {
        let mut graph = DecisionGraph::new();
        graph.add_rule_from_str("base:delete user:keep **").unwrap();
        graph
            .add_rule_from_str("base:keep user:keep .config/xfce4/xfconf/xfce-perchannel-xml")
            .unwrap();
        graph
            .add_rule_from_str("base:keep user:keep .config/xfce4/panel")
            .unwrap();
        graph
            .add_rule_from_str("base:keep user:delete .local/share/applications")
            .unwrap();
        graph
            .add_rule_from_str("base:keep user:delete .lapas")
            .unwrap();
        graph
            .add_rule_from_str("base:keep user:delete .bashrc")
            .unwrap();
        graph
            .add_rule_from_str("base:keep user:delete .bash_profile")
            .unwrap();
        graph
            .add_rule_from_str("base:keep user:delete .wineManager")
            .unwrap();
        graph
            .add_rule_from_str("base:delete user:keep .wineManager/bottles/*/prefix/user.reg")
            .unwrap();
        graph
            .add_rule_from_str("base:delete user:keep .wineManager/bottles/*/prefix/userdef.reg")
            .unwrap();
        graph
            .add_rule_from_str("base:delete user:keep .wineManager/userdata")
            .unwrap();
        graph
            .add_rule_from_str("base:keep user:delete .keep")
            .unwrap();
        graph
    }

    #[test]
    fn correct_typical_lapas() {
        let graph = construct_typical_lapas_graph();
        graph
            .write_dot_to_file("/tmp/correct_typical_lapas.dot")
            .unwrap();
        graph_assert!(graph, ".wineManager", true, Keep, Delete);
        graph_assert!(graph, ".wineManager/helpers", false, Keep, Delete);
        graph_assert!(graph, ".wineManager/userdata", false, Delete, Keep);
        graph_assert!(graph, ".wineManager/bottles", true, Keep, Delete);
        graph_assert!(graph, ".wineManager/bottles/game0", true, Keep, Delete);
        graph_assert!(
            graph,
            ".wineManager/bottles/game0/prefix",
            true,
            Keep,
            Delete
        );
        graph_assert!(
            graph,
            ".wineManager/bottles/game0/prefix/drive_c",
            false,
            Keep,
            Delete
        );
        graph_assert!(
            graph,
            ".wineManager/bottles/game0/prefix/user.reg",
            false,
            Delete,
            Keep
        );
        graph_assert!(
            graph,
            ".wineManager/bottles/game0/prefix/userdef.reg",
            false,
            Delete,
            Keep
        );

        graph_assert!(graph, ".local", true, Delete, Keep);
        graph_assert!(graph, ".local/share", true, Delete, Keep);
        graph_assert!(graph, ".local/share/applications", false, Keep, Delete);
    }

    #[test]
    fn correct_absolute_rule_ordering() {
        let mut graph = DecisionGraph::new();
        graph
            .add_rule_from_str("base:delete user:keep .config")
            .unwrap();
        graph.add_rule_from_str("base:keep user:delete *").unwrap();
        graph
            .add_rule_from_str("base:delete user:keep .config/xfce4")
            .unwrap();
        //graph.write_dot_to_file("/tmp/correct_absolute_rule_ordering.dot").unwrap();
        graph_assert!(graph, ".config", true, Keep, Delete);
        graph_assert!(graph, ".config/test.xml", false, Keep, Delete);
        graph_assert!(graph, ".config/xfce4", false, Delete, Keep);
        graph_assert!(graph, ".config/xfce4/test.xml", false, Delete, Keep);
    }
}
