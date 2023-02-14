mod dns_service;
mod user_service;
mod notification_service;

use std::collections::HashMap;
use std::net::SocketAddr;
use std::os::unix::prelude::PermissionsExt;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{anyhow, Result, Context};
use dns_service::DnsService;
use notification_service::NotificationService;
use rand::Rng;
use rand::distributions::Alphanumeric;
use sha2::{Sha512, Digest};
use tokio::fs::File;
use tokio::net::{TcpStream, TcpListener};
use tokio::io::{AsyncWriteExt, BufReader, AsyncBufReadExt};
use clap::Parser;
use lapas_api_proto::{LapasProtocol, ProtoSerde, ApiPassword};
use tokio::sync::Mutex;
use user_service::UserService;

struct State {
    config: HashMap<String, String>,
    root_nonce: String,
    user_service: Mutex<UserService>,
    dns_service: Mutex<DnsService>,
    notification_service: NotificationService
}
impl State {
    pub async fn init(args: &CliArgs) -> Result<State> {
        let mut config = HashMap::new();

        let config_file = File::open(&args.config_file).await
            .context("Failed to open lapas scripts configuration file.")?;
        let mut config_file_lines = BufReader::new(config_file).lines();
        while let Some(line) = config_file_lines.next_line().await? {
            if line.starts_with("#") { continue; }
            let line_parts: Vec<_> = line.splitn(2, "=").collect();
            if line_parts.len() != 2 { return Err(anyhow!("Invalid config file")); }
            let key = line_parts[0];
            let mut value = line_parts[1];
            if value.len() > 1 && value.starts_with("\"") && value.ends_with("\"") {
                value = &value[1..value.len()-1];
            }
            config.insert(key.to_owned(), value.to_owned());
        }

        let scripts_dir = config.get("LAPAS_SCRIPTS_DIR")
            .expect("Config File missing parameter LAPAS_SCRIPTS_DIR")
            .clone();
        let guest_root_dir = config.get("LAPAS_GUESTROOT_DIR")
            .expect("Config File missing parameter LAPAS_GUESTROOT_DIR")
            .clone();
        let dns_domain = config.get("LAPAS_NET_DOMAIN")
            .expect("Config File missing parameter LAPAS_NET_DOMAIN")
            .clone();
        let dns_hostmap_dir = config.get("LAPAS_DNS_HOSTMAPPINGS_DIR")
            .expect("Config File missing parameter LAPAS_DNS_HOSTMAPPINGS_DIR")
            .clone();

        // generate random root nonce that can be used for root logins.
        // This root_nonce will then be written to the guest's lapas directory (only root-accessible)
        let root_nonce: String = rand::thread_rng()
            .sample_iter(&Alphanumeric)
            .take(128)
            .map(char::from)
            .collect();
        let mut root_nonce_file = PathBuf::from(guest_root_dir);
        root_nonce_file.push("lapas");
        root_nonce_file.push("apiserver_root_nonce.env");
        let mut root_nonce_file = File::create(root_nonce_file).await?;
        root_nonce_file.write_all(format!("ROOT_NONCE=\"{}\"\n", root_nonce).as_bytes()).await?;
        root_nonce_file.flush().await?;
        let mut root_nonce_file_permissions = root_nonce_file.metadata().await?.permissions();
        // only root accessible
        root_nonce_file_permissions.set_mode(0);
        root_nonce_file.set_permissions(root_nonce_file_permissions).await?;

        Ok(State {
            config,
            root_nonce,
            user_service: Mutex::new(UserService::new(scripts_dir)),
            dns_service: Mutex::new(DnsService::new(dns_domain, dns_hostmap_dir).await?),
            notification_service: NotificationService::new()
        })
    }

    fn password_salt(&self) -> &str {
        self.config.get("LAPAS_PASSWORD_SALT").expect("Config File missing parameter LAPAS_PASSWORD_SALT")
    }
    fn password_hash(&self) -> &str {
        self.config.get("LAPAS_PASSWORD_HASH").expect("Config File missing parameter LAPAS_PASSWORD_HASH")
    }
    fn dns_domain(&self) -> &str {
        self.config.get("LAPAS_NET_DOMAIN").expect("Config File missing parameter LAPAS_NET_DOMAIN")
    }

    pub fn check_auth(&self, password: ApiPassword) -> bool {
        match password {
            ApiPassword::RootNonce(root_nonce) => {
                root_nonce == self.root_nonce
            },
            ApiPassword::Plain(api_password) => {
                let salted_password = format!("{}{}", self.password_salt(), api_password); // prepend salt
                let mut hasher = Sha512::new();
                hasher.update(salted_password.as_bytes());
                let salted_password_hash = hex::encode(hasher.finalize());
                self.password_hash() == salted_password_hash
            },
        }
    }

    pub async fn add_user(&self, username: String, password: String) -> Result<()> {
        let user_service = self.user_service.lock().await;
        let result = user_service.add_user(username, password).await;
        if let Ok(_) = result {
            self.notify(LapasProtocol::NotifyRootChanged {});
        }
        result
    }

    pub async fn create_user_host_mapping(&self, username: String, addr: SocketAddr) -> Result<()> {
        let dns_service = self.dns_service.lock().await;
        let result = dns_service.create_mapping(username, addr).await;
        if let Ok(_) = result {
            self.notify(LapasProtocol::NotifyDnsMappingsChanged{});
        }
        result
    }

    pub async fn run_notification_service(&self, stream: TcpStream) -> Result<()> {
        self.notification_service.run(stream).await
    }

    pub fn notify(&self, notification: LapasProtocol) {
        self.notification_service.send(notification);
    }
}

type SharedState = Arc<State>;

async fn handle_client(mut stream: TcpStream, state: SharedState) -> Result<()> {
    let peer_addr = stream.peer_addr()?;

    let pkt = LapasProtocol::decode(&mut stream).await?;
    if let LapasProtocol::RequestHello { version, password } = pkt {
        if version != lapas_api_proto::VERSION {
            println!("Client[{}] Incompatible Protocol Version", peer_addr);
            LapasProtocol::ResponseResult { result: Err("Incompatible Protocol Version".to_owned()) }
                .encode(&mut stream).await?;
            stream.shutdown().await?;
            return Ok(());
        }
        if !state.check_auth(password) {
            println!("Client[{}] Authentication Failed", peer_addr);
            LapasProtocol::ResponseResult { result: Err("Authentication Failed".to_owned()) }
                .encode(&mut stream).await?;
            stream.shutdown().await?;
            return Ok(());
        }
    } else {
        stream.shutdown().await?;
        return Ok(());
    }
    LapasProtocol::ResponseResult { result: Ok(()) }.encode(&mut stream).await?;

    // start handling requests
    while let Ok(request) = LapasProtocol::decode(&mut stream).await {
        match request {
            LapasProtocol::RequestPing {  } => {
                LapasProtocol::ResponseResult { result: Ok(()) }.encode(&mut stream).await?;
            },
            LapasProtocol::RequestAddUser { username, password } => {
                println!("Client[{}] Adding User: {} ...", peer_addr, username);
                let result = state.add_user(username.clone(), password).await
                    .map_err(|e| e.to_string());
                match &result {
                    Ok(_) => println!("Client[{}] Adding User: {} succeeded", peer_addr, username),
                    Err(e) => println!("Client[{}] Adding User: {} failed:\n{}", peer_addr, username, e),
                }
                LapasProtocol::ResponseResult { result }.encode(&mut stream).await?;
            },
            LapasProtocol::RequestDnsMapping { username } => {
                println!("Client[{}] IP now mapped to: {}.{} ...", peer_addr, username, state.dns_domain());
                let result = state.create_user_host_mapping(username.clone(), peer_addr).await
                    .map_err(|e| e.to_string());
                match &result {
                    Ok(_) => println!("Client[{}] Mapping IP to: {}.{} succeeded", peer_addr, username, state.dns_domain()),
                    Err(e) => println!("Client[{}] Mapping IP to: {}.{} failed:\n{}", peer_addr, username, state.dns_domain(), e),
                }
                LapasProtocol::ResponseResult { result }.encode(&mut stream).await?;
            },
            LapasProtocol::SwitchNotify {} => {
                LapasProtocol::ResponseResult { result: Ok(()) }.encode(&mut stream).await?;
                return state.run_notification_service(stream).await;
            },
            _ => return Err(anyhow!("Client[{}] Received unexpected packet!", peer_addr))
        }
    }

    Ok(())
}


#[derive(Debug, Parser)]
#[command(name = "lapas_api_server")]
#[command(author, version, about)]
struct CliArgs {
    /// Path to the lapas script configuration file
    #[arg(long = "config", value_name = "CONFIG")]
    config_file: PathBuf
}


#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args = CliArgs::parse();
    let state = Arc::new(State::init(&args).await?);

    // start server
    println!("Starting LAPAS API Server [Protocol Version: {}]", lapas_api_proto::VERSION);
    let listener = TcpListener::bind(("0.0.0.0", 1337)).await?;
    println!("Listening on 0.0.0.0:1337");
    loop {
        let (client_stream, addr) = listener.accept().await?;
        tokio::spawn({let state = state.clone(); async move {
            println!("Client[{}] Connected", addr);
            let _ = handle_client(client_stream, state).await;
            println!("Client[{}] Disconnected", addr);
        }});
    }
}