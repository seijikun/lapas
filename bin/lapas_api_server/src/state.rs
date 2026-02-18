use anyhow::{Context as _, Result, anyhow};
use lapas_api_proto::{ApiAuth, LapasProtocol, LapasUserPasswd, LapasUserShadow};
use sha2::{Digest as _, Sha512};
use std::{collections::HashMap, net::SocketAddr, path::Path, sync::Arc};
use tokio::{fs::File, io::{AsyncBufReadExt as _, BufReader}, sync::Mutex};
use crate::api_services::{PeerTx, dns::DnsService, notification::NotificationService, user::UserService};

pub type SharedState = Arc<State>;

pub struct State {
    config: HashMap<String, String>,
    user_service: Mutex<UserService>,
    dns_service: Mutex<DnsService>,
    notification_service: NotificationService,
}
impl State {
    pub async fn init(config_path: &Path) -> Result<State> {
        let mut config = HashMap::new();

        let config_file = File::open(config_path)
            .await
            .context("Failed to open lapas scripts configuration file.")?;
        let mut config_file_lines = BufReader::new(config_file).lines();
        while let Some(line) = config_file_lines.next_line().await? {
            if line.starts_with("#") {
                continue;
            }
            let line_parts: Vec<_> = line.splitn(2, "=").collect();
            if line_parts.len() != 2 {
                return Err(anyhow!("Invalid config file"));
            }
            let key = line_parts[0];
            let mut value = line_parts[1];
            if value.len() > 1 && value.starts_with("\"") && value.ends_with("\"") {
                value = &value[1..value.len() - 1];
            }
            config.insert(key.to_owned(), value.to_owned());
        }

        let homes_dir = config
            .get("LAPAS_USERHOMES_DIR")
            .expect("Config File missing parameter LAPAS_USERHOMES_DIR")
            .clone();
        let dns_domain = config
            .get("LAPAS_NET_DOMAIN")
            .expect("Config File missing parameter LAPAS_NET_DOMAIN")
            .clone();
        let dns_hostmap_dir = config
            .get("LAPAS_DNS_HOSTMAPPINGS_DIR")
            .expect("Config File missing parameter LAPAS_DNS_HOSTMAPPINGS_DIR")
            .clone();

        Ok(State {
            config,
            user_service: Mutex::new(UserService::new(homes_dir).await?),
            dns_service: Mutex::new(DnsService::new(dns_domain, dns_hostmap_dir).await?),
            notification_service: NotificationService::new(),
        })
    }

    fn password_salt(&self) -> &str {
        self.config
            .get("LAPAS_PASSWORD_SALT")
            .expect("Config File missing parameter LAPAS_PASSWORD_SALT")
    }
    fn password_hash(&self) -> &str {
        self.config
            .get("LAPAS_PASSWORD_HASH")
            .expect("Config File missing parameter LAPAS_PASSWORD_HASH")
    }

    pub fn check_auth(&self, auth: ApiAuth) -> bool {
        match auth {
            ApiAuth::Password(api_password) => {
                let salted_password = format!("{}{}", self.password_salt(), api_password); // prepend salt
                let mut hasher = Sha512::new();
                hasher.update(salted_password.as_bytes());
                let salted_password_hash = hex::encode(hasher.finalize());
                self.password_hash() == salted_password_hash
            }
        }
    }

    pub async fn add_user(&self, username: String, password: String) -> Result<()> {
        let user_service = self.user_service.lock().await;
        let result = user_service.add_user(username, password).await;
        if let Ok(_) = result {
            self.notify(LapasProtocol::NotifyUsersChanged {});
        }
        result
    }

    pub async fn create_user_host_mapping(&self, username: String, addr: SocketAddr) -> Result<()> {
        let dns_service = self.dns_service.lock().await;
        let result = dns_service.create_mapping(username, addr).await;
        if let Ok(_) = result {
            self.notify(LapasProtocol::NotifyDnsMappingsChanged {});
        }
        result
    }

    pub async fn passwd_all(&self) -> Result<Vec<LapasUserPasswd>> {
        let user_service = self.user_service.lock().await;
        user_service.passwd_all().await
    }

    pub async fn shadow_all(&self) -> Result<Vec<LapasUserShadow>> {
        let user_service = self.user_service.lock().await;
        user_service.shadow_all().await
    }

    pub async fn register_event_listener(&self, tx: PeerTx) {
        self.notification_service.add(tx).await
    }

    pub fn notify(&self, notification: LapasProtocol) {
        self.notification_service.send(notification);
    }
}