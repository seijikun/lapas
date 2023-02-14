use std::time::Duration;

use anyhow::{anyhow, Result, Context};
use lapas_api_proto::{LapasProtocol, ProtoSerde};
use tokio::{time, process::Command};

use crate::{CliArgs, perform_request, connect_and_authenticate};

pub(crate) async fn run(args: &CliArgs) -> Result<()> {
    let mut stream = connect_and_authenticate(args).await?;
    println!("Connected");

    perform_request(
        &mut stream,
        LapasProtocol::SwitchNotify {}
    ).await.context("Switch to Notification Mode")?.map_err(|msg| anyhow!(msg))?;

    loop {
        tokio::select! {
            _ = time::sleep(Duration::from_millis(1000)) => {
                LapasProtocol::RequestPing{}.encode(&mut stream).await?;
            },
            pkt = LapasProtocol::decode(&mut stream) => {
                let pkt = pkt?;
                match pkt {
                    LapasProtocol::RequestPing {} => {
                        LapasProtocol::ResponseResult{ result: Ok(()) }.encode(&mut stream).await?;
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