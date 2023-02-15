use std::{path::PathBuf, process::Stdio};
use tokio::process::Command;

use anyhow::{anyhow, Result};

pub(crate) struct UserService {
    add_user_bin: PathBuf
}
impl UserService {
    pub fn new(script_dir: String) -> Self {
        let mut add_user_bin = PathBuf::from(script_dir);
        add_user_bin.push("addUser.sh");
        Self { add_user_bin }
    }

    pub async fn add_user(&self, username: String, password: String) -> Result<()> {
        let mut error_str = String::new();
        for i in 0..5 {
            error_str += &format!("####################\nAttempt {}/4:\n", i + 1);
            let process = Command::new(&self.add_user_bin)
                .arg(&username)
                .arg(&password)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()?
                .wait_with_output().await?;
            // any result/failure up till now is critical, because it means that we couldn't even
            // successfully start the addUser script.
            if process.status.success() {
                return Ok(());
            } else {
                error_str += &String::from_utf8_lossy(&process.stderr);
                error_str += &String::from_utf8_lossy(&process.stdout);
                error_str += "\n";
            }
        }

        Err(anyhow!("Adding user {} failed:\n{}", username, error_str))
    }

}