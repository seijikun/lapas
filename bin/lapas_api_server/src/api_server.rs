use std::net::SocketAddr;

use anyhow::{anyhow, Result};
use tokio::net::TcpListener;
use crate::{api_services::{PeerRx, PeerTx}, state::SharedState};
use lapas_api_proto::LapasProtocol;

#[derive(Clone)]
struct ClientContext {
    addr: SocketAddr,
}
impl ClientContext {
    pub fn log<M: ToString>(&self, msg: M) {
        println!("Client[{}]: {}", self.addr.ip(), msg.to_string());
    }
}

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



pub async fn run(state: SharedState) -> Result<()> {
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