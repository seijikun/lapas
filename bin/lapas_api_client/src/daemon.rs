use std::time::Duration;

use anyhow::{anyhow, Result, Context};
use lapas_api_proto::{LapasProtocol, ProtoSerde};
use tokio::{time, net::TcpStream, io::AsyncWriteExt, process::Command};

use crate::{CliArgs, perform_request, connect};

pub(crate) async fn run(args: &CliArgs) -> Result<()> {
    async fn inner(stream: &mut TcpStream) -> Result<()> {
        perform_request(
            stream,
            LapasProtocol::SwitchNotify {}
        ).await.context("Switch to Notification Mode")?.map_err(|msg| anyhow!(msg))?;

        loop {
            tokio::select! {
                _ = time::sleep(Duration::from_millis(1000)) => {
                    LapasProtocol::RequestPing{}.encode(stream).await?;
                },
                pkt = LapasProtocol::decode(stream) => {
                    let pkt = pkt?;
                    match pkt {
                        LapasProtocol::RequestPing {} => {
                            LapasProtocol::ResponseResult{ result: Ok(()) }.encode(stream).await?;
                        },
                        LapasProtocol::ResponseResult { result: _ } => {}, // client ping response
                        LapasProtocol::NotifyRootChanged{} => handle_root_changed().await,
                        _ => { // error - unknown packet
                            Err(anyhow!("Received invalid Packet"))?;
                        }
                    }
                }
            };
        }
    }

    loop {
        match connect(args).await {
            Ok(mut connection) => {
                println!("Connected");
                match inner(&mut connection).await {
                    Ok(()) => {},
                    Err(e) => println!("Disconnected\n{}", e),
                }
                let _ = connection.shutdown().await;
            },
            Err(e) => println!("Connecting failed: {}", e),
        }
        time::sleep(Duration::from_millis(1000)).await;
        println!("Retrying...");
    }
}

async fn handle_root_changed() {
    println!("[Event] Root Changed");
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