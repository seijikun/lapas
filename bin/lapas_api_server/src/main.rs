mod dns_service;
mod notification_service;
mod user_service;

use std::collections::HashMap;
use std::net::SocketAddr;
use std::ops::DerefMut;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use clap::Parser;
use dns_service::DnsService;
use lapas_api_proto::{ApiAuth, LapasProtocol, LapasUserPasswd, LapasUserShadow, ProtoSerde};
use notification_service::NotificationService;
use sha2::{Digest, Sha512};
use tokio::fs::File;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpListener;
use tokio::sync::Mutex;
use user_service::UserService;

#[derive(Clone)]
struct PeerTx {
    tx: Arc<Mutex<OwnedWriteHalf>>,
}
impl PeerTx {
    pub fn new(tx: OwnedWriteHalf) -> Self {
        Self {
            tx: Arc::new(Mutex::new(tx)),
        }
    }
    pub async fn shutdown(&self) {
        let _ = self.tx.lock().await.shutdown().await;
    }
    pub async fn send(&self, packet: LapasProtocol) -> Result<()> {
        let mut tx = self.tx.lock().await;
        packet.encode(tx.deref_mut()).await?;
        Ok(())
    }
}

struct PeerRx {
    rx: OwnedReadHalf,
}
impl PeerRx {
    pub fn new(rx: OwnedReadHalf) -> Self {
        Self { rx }
    }
    pub async fn recv(&mut self) -> Result<LapasProtocol> {
        Ok(LapasProtocol::decode(&mut self.rx).await?)
    }
}

#[derive(Clone)]
struct ClientContext {
    addr: SocketAddr,
}
impl ClientContext {
    pub fn log<M: ToString>(&self, msg: M) {
        println!("Client[{}]: {}", self.addr.ip(), msg.to_string());
    }
}

struct State {
    config: HashMap<String, String>,
    user_service: Mutex<UserService>,
    dns_service: Mutex<DnsService>,
    notification_service: NotificationService,
}
impl State {
    pub async fn init(args: &CliArgs) -> Result<State> {
        let mut config = HashMap::new();

        let config_file = File::open(&args.config_file)
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

type SharedState = Arc<State>;

async fn handle_handshake(rx: &mut PeerRx, tx: &PeerTx) -> Result<()> {
    let pkt = rx.recv().await?;
    if let LapasProtocol::ControlHandshake { version } = pkt {
        if version != lapas_api_proto::VERSION {
            tx.send(LapasProtocol::ControlHandshakeResponse {
                result: Err("Incompatible Protocol Version".to_string()),
            })
            .await?;
            return Err(anyhow!("Incompatible Protocol Version"));
        }
    } else {
        return Err(anyhow!("Received unexpected packet!"));
    }
    tx.send(LapasProtocol::ControlHandshakeResponse { result: Ok(()) })
        .await?;
    Ok(())
}

macro_rules! handle_request {
    ($state:ident, $tx:ident, $(@auth_with($auth:ident),)? $response_pkt:ident = {
        $result_expr:expr;
        $(Ok = $ok_expr:expr;)?
        $(Err = $err_expr:expr;)?
    }) => {
        $(
            if !$state.check_auth($auth) {
                let result = Err("Authentication failed".to_string());
                $tx.send(LapasProtocol::$response_pkt { result }).await?;
                return Err(anyhow!("Authentication failed"));
            }
        )?
        let result = $result_expr.map_err(|e| e.to_string());
        match &result {
            Ok(_) => {$(($ok_expr)())?},
            #[allow(unused_variables)]
            Err(e) => {$(($err_expr)(e))?},
        }
        $tx.send(LapasProtocol::$response_pkt { result }).await?;
    };
}

async fn handle_client(
    mut rx: PeerRx,
    tx: PeerTx,
    ctx: ClientContext,
    state: SharedState,
) -> Result<()> {
    // Handshake
    handle_handshake(&mut rx, &tx).await?;

    // start handling requests
    loop {
        match rx.recv().await? {
            LapasProtocol::ControlListenEvents {} => {
                state.register_event_listener(tx.clone()).await;
                ctx.log("Registered for events");
            }
            LapasProtocol::ControlCheckAuth { auth } => {
                handle_request!(state, tx, @auth_with(auth), ControlCheckAuthResponse = {
                    {let result: Result<(), String> = Ok(()); result};
                });
            }

            LapasProtocol::UserRegister {
                auth,
                new_username,
                new_password,
            } => {
                handle_request!(state, tx, @auth_with(auth), UserRegisterResponse = {
                    state.add_user(new_username.clone(), new_password).await;
                    Ok = || ctx.log(format!("Successfully registered user: {}", new_username));
                    Err = |e| ctx.log(format!("Failed to register new user: {}\n{}", new_username, e));
                });
            }
            LapasProtocol::UserDnsMapping { auth, username } => {
                handle_request!(state, tx, @auth_with(auth), UserDnsMappingResponse = {
                    state.create_user_host_mapping(username.clone(), ctx.addr).await;
                    Ok = || ctx.log(format!("Usermapping created to: {}", username));
                    Err = |e| ctx.log(format!("Failed to create usermapping to: {}\n{}", username, e));
                });
            }

            LapasProtocol::PasswdGetList => {
                handle_request!(
                    state,
                    tx,
                    PasswdGetListResponse = {
                        state.passwd_all().await;
                        Ok = || ctx.log("Requested passwd");
                        Err = |e| ctx.log(format!("Failed to send passwd:\n{}", e));
                    }
                );
            }

            LapasProtocol::ShadowGetList { auth } => {
                handle_request!(state, tx, @auth_with(auth), ShadowGetListResponse = {
                    state.shadow_all().await;
                    Ok = || ctx.log("Requested passwd");
                    Err = |e| ctx.log(format!("Failed to send passwd:\n{}", e));
                });
            }

            _ => {}
        }
    }
}

#[derive(Debug, Parser)]
#[command(name = "lapas_api_server")]
#[command(author, version, about)]
struct CliArgs {
    /// Path to the lapas script configuration file
    #[arg(long = "config", value_name = "CONFIG")]
    config_file: PathBuf,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args = CliArgs::parse();
    let state = Arc::new(State::init(&args).await?);

    // start server
    println!(
        "Starting LAPAS API Server [Protocol Version: {}]",
        lapas_api_proto::VERSION
    );
    let listener = TcpListener::bind(("0.0.0.0", 1337)).await?;
    println!("Listening on 0.0.0.0:1337");
    loop {
        let (client_stream, addr) = listener.accept().await?;
        tokio::spawn({
            let state = state.clone();
            async move {
                let clog = ClientContext { addr };
                clog.log("Connected");
                let (rx, tx) = client_stream.into_split();
                let (rx, tx) = (PeerRx::new(rx), PeerTx::new(tx));
                if let Err(e) = handle_client(rx, tx.clone(), clog.clone(), state).await {
                    clog.log(format!("Error: {}", e));
                }
                tx.shutdown().await;
                clog.log("Disconnected");
            }
        });
    }
}
