use std::{time::Duration, path::PathBuf, sync::Arc, ops::Deref, os::unix::prelude::PermissionsExt};

use anyhow::{anyhow, Result, Context};
use lapas_api_proto::{LapasProtocol, ProtoSerde, LapasUserShadow, ApiAuth, LapasUserPasswd};
use sd_notify::NotifyState;
use tokio::{time, process::Command, fs, net::{UnixListener, TcpStream, UnixStream}, sync::Mutex};

use crate::{CliArgs, lapas_connect, args_to_auth};

const LAPAS_AUTH_RUNDIR: &'static str = "/run/lapas";
const LAPAS_AUTH_SOCKET_NAME: &'static str = "auth_serv.socket";

struct UserCache {
    user_cache: Mutex<Option<Vec<LapasUserShadow>>>
}
impl UserCache {
    pub fn new() -> Self {
        Self { user_cache: Mutex::new(None) }
    }
    pub async fn set(&self, users: Vec<LapasUserShadow>) {
        let mut user_cache = self.user_cache.lock().await;
        *user_cache = Some(users);
    }
    pub async fn get(&self) -> Vec<LapasUserShadow> {
        // wait up to 5 secs for a user list
        for _ in 0..50 {
            {
                let user_cache = self.user_cache.lock().await;
                if let Some(user_cache) = user_cache.deref() {
                    return user_cache.clone();
                }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        // cache wasn't ready in time, respond with empty list
        // there is probably something horribly wrong here!
        eprintln!("AuthServer: WARNING. Usercache wasn't ready in time!");
        vec![]
    }
}
type UserCacheState = Arc<UserCache>;

async fn handle_local_auth_client(auth: ApiAuth, user_cache: UserCacheState, mut stream: UnixStream) -> Result<()> {
    if let LapasProtocol::ControlHandshake { version } = LapasProtocol::decode(&mut stream).await? {
        if version != lapas_api_proto::VERSION {
            LapasProtocol::ControlHandshakeResponse { result: Err("AuthServ: Incompatible Protocol Version".to_string()) }
                .encode(&mut stream).await?;
            return Err(anyhow!("AuthServ: Incompatible Protocol Version"));
        }
    } else {
        return Err(anyhow!("AuthServ: Received unexpected packet!"));
    }
    LapasProtocol::ControlHandshakeResponse { result: Ok(()) }.encode(&mut stream).await?;

    let pkt = LapasProtocol::decode(&mut stream).await?;
    match pkt {
        LapasProtocol::PasswdGetList => {
            println!("AuthServ: Got Passwd request");
            let user_list = user_cache.get().await
                .into_iter()
                .map(|u| LapasUserPasswd { id: u.id, name: u.name })
                .collect();
            LapasProtocol::PasswdGetListResponse { result: Ok(user_list) }.encode(&mut stream).await?;
        },
        LapasProtocol::ShadowGetList { auth: is_auth } => {
            println!("AuthServ: Got Shadow request");
            match (is_auth, auth) {
                (ApiAuth::Password(auth_is), ApiAuth::Password(auth_should)) if auth_is == auth_should => {
                    let user_list = user_cache.get().await;
                    LapasProtocol::ShadowGetListResponse { result: Ok(user_list) }.encode(&mut stream).await?;
                },
                _ => eprintln!("AuthServ: API Authentication failed!")
            }
        },
        _ => {}
    }
    Ok(())
}

async fn run_local_auth_server(auth: ApiAuth, user_cache: UserCacheState) -> Result<()> {
    fs::create_dir_all(LAPAS_AUTH_RUNDIR).await?;
    let mut auth_socket_path = PathBuf::from(LAPAS_AUTH_RUNDIR);
    auth_socket_path.push(LAPAS_AUTH_SOCKET_NAME);
    if auth_socket_path.exists() {
        fs::remove_file(&auth_socket_path).await?;
    }
    let listener = UnixListener::bind(&auth_socket_path)?;

    // allow everyone to access auth server unix socket
    let mut auth_socket_permissions = fs::metadata(&auth_socket_path).await?.permissions();
    auth_socket_permissions.set_mode(0o777);
    fs::set_permissions(auth_socket_path, auth_socket_permissions).await?;

    println!("AuthServ: Ready - notifying systemd...");
    let _ = sd_notify::notify(true, &[NotifyState::Ready]);

    loop {
        match listener.accept().await {
            Ok((stream, _addr)) => {
                tokio::spawn(handle_local_auth_client(auth.clone(), user_cache.clone(), stream));
            },
            Err(e) => {
                eprintln!("AuthServ: Connection attempt failed:\n{}", e);
            }
        }
    }
}

pub(crate) async fn run(args: &CliArgs) -> Result<()> {
    let auth = args_to_auth(args)?;

    let auth_cache = UserCacheState::new(UserCache::new());
    tokio::spawn({
        let auth = auth.clone();
        let auth_cache = auth_cache.clone();
        async move {
        loop {
            println!("AuthServ: Starting...");
            let result = run_local_auth_server(auth.clone(), auth_cache.clone()).await;
            if let Err(e) = result {
                eprintln!("AuthServ: Crashed: {}", e);
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    }});

    loop {
        println!("Connecting to lapas api server");
        if let Err(e) = run_daemon(args, auth.clone(), auth_cache.clone()).await {
            println!("Lost connection to lapas api server: {}", e);
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
}

async fn run_daemon(args: &CliArgs, auth: ApiAuth, auth_cache: UserCacheState) -> Result<()> {
    let mut connection = lapas_connect(&args).await?;
    println!("Connected to lapas api server");
    LapasProtocol::ControlListenEvents.encode(&mut connection).await
        .context("Registering for server events")?;
    LapasProtocol::ShadowGetList { auth: auth.clone() }.encode(&mut connection).await
        .context("Request shadow list for initial cache warming")?;

    loop {
        tokio::select! {
            _ = time::sleep(Duration::from_millis(1000)) => {
                LapasProtocol::ControlPing.encode(&mut connection).await?;
            },
            pkt = LapasProtocol::decode(&mut connection) => {
                let pkt = pkt?;
                match pkt {
                    LapasProtocol::ControlPing => {},
                    LapasProtocol::NotifyRootChanged{} => handle_root_changed().await,
                    LapasProtocol::NotifyUsersChanged {} => handle_users_changed(&mut connection, &auth).await?,
                    LapasProtocol::NotifyDnsMappingsChanged{} => handle_dns_mappings_changed().await,
                    LapasProtocol::ShadowGetListResponse { result } => {
                        match result {
                            Ok(user_list) => auth_cache.set(user_list).await, // update cache
                            Err(e) => {
                                return Err(anyhow!("Acquiring new user shadow listing failed:\n{}", e));
                            }
                        }
                    },
                    _ => { } // unhandled packet
                }
            }
        };
    }
}

async fn handle_root_changed() {
    println!("[Event] Root filesystem changed");
    tokio::time::sleep(Duration::from_secs(2)).await;
    println!("Remounting root filesystem...");
    let child = Command::new("/usr/bin/mount")
        .args(&["-o", "remount", "/"])
        .spawn();
    match child {
        Ok(mut child) => {
            match child.wait().await {
                Ok(result) if result.success() => {
                    println!("Successfully remounted root filesystem");
                },
                _ => println!("Failed to remount root filesystem")
            }
        },
        Err(e) => {
            println!("Failed to remount root filesystem: {}", e);
        },
    }
}

async fn handle_dns_mappings_changed() {
    println!("[Event] DNS Mappings changed");
    println!("Flusing DNS cache...");
    let child = Command::new("/usr/bin/resolvectl")
        .arg("flush-caches")
        .spawn();
    match child {
        Ok(mut child) => {
            match child.wait().await {
                Ok(result) if result.success() => {
                    println!("Successfully flushed DNS cache");
                },
                _ => println!("Failed to flush DNS cache")
            }
        },
        Err(e) => {
            println!("Failed to flush DNS cache: {}", e);
        },
    }
}

async fn handle_users_changed(connection: &mut TcpStream, auth: &ApiAuth) -> Result<()> {
    println!("[Event] Registered users changed");
    // request user listing to refresh local cache
    LapasProtocol::ShadowGetList { auth: auth.clone() }.encode(connection).await?;
    Ok(())
}
