use std::time::Duration;

use lapas_api_proto::{LapasProtocol, ProtoSerde};
use tokio::{net::{TcpStream, tcp::{OwnedReadHalf, OwnedWriteHalf}}, sync::{broadcast::{self, Receiver}}, time, io::AsyncWriteExt};
use anyhow::{Result, anyhow};

pub(crate) struct NotificationService {
    notifier: broadcast::Sender<LapasProtocol>
}
impl NotificationService {
    pub fn new() -> Self {
        let (notifier, _) = broadcast::channel(1);
        Self { notifier }
    }

    pub fn send(&self, notification: LapasProtocol) {
        println!("Sending Notification: {:?}", notification);
        let _ = self.notifier.send(notification);
    }

    pub async fn run(&self, stream: TcpStream) -> Result<()> {
        let peer_addr = stream.peer_addr()?;
        println!("Client[{}] Entering notification service", peer_addr);

        let (mut stream_rx, mut stream_tx) = stream.into_split();
        let mut notify_rx = self.notifier.subscribe();
        async fn inner(stream_rx: &mut OwnedReadHalf, stream_tx: &mut OwnedWriteHalf, notify_rx: &mut Receiver<LapasProtocol>) -> Result<()> {
            loop {
                tokio::select! {
                    notification = notify_rx.recv() => {
                        let notification = notification?;
                        notification.encode(stream_tx).await?;
                    },
                    _ = time::sleep(Duration::from_millis(1000)) => {
                        LapasProtocol::RequestPing{}.encode(stream_tx).await?;
                    },
                    pkt = LapasProtocol::decode(stream_rx) => {
                        let pkt = pkt?;
                        match pkt {
                            LapasProtocol::RequestPing {} => {
                                LapasProtocol::ResponseResult{ result: Ok(()) }.encode(stream_tx).await?;
                            },
                            LapasProtocol::ResponseResult { result: _ } => {}, // client ping response
                            _ => { // error - unknown packet
                                Err(anyhow!("Received invalid Packet"))?;
                            }
                        }
                    }
                };
            }
        }

        let _ = inner(&mut stream_rx, &mut stream_tx, &mut notify_rx).await;
        let _ = stream_tx.shutdown().await;
        Ok(())
    }
}