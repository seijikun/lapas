use std::{path::PathBuf, net::SocketAddr};
use anyhow::{anyhow, Result};
use tokio::io::AsyncWriteExt;

pub(crate) struct DnsService {
    dns_domain: String,
    hosts_dir: PathBuf
}
impl DnsService {
    pub async fn new(dns_domain: String, hosts_dir: String) -> Result<Self> {
        let hosts_dir = PathBuf::from(hosts_dir);
        if !hosts_dir.exists() {
            tokio::fs::create_dir_all(&hosts_dir).await?;
        }
        if !hosts_dir.is_dir() {
            return Err(anyhow!("Failed to create dnsmasq hostsdir!"));
        }
        Ok(Self { dns_domain, hosts_dir })
    }

    pub async fn create_mapping(&self, username: String, addr: SocketAddr) -> Result<()> {
        let mut user_file = self.hosts_dir.clone();
        user_file.push(&username);
        let mut user_file = tokio::fs::File::create(user_file).await?;
        let mapping = format!("{} {}.{}\n", addr.ip().to_string(), username, self.dns_domain);
        user_file.write_all(&mapping.as_bytes()).await?;
        user_file.flush().await?;
        Ok(())
    }

}
