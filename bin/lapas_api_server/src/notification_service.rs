use std::time::Duration;

use lapas_api_proto::LapasProtocol;
use tokio::{sync::{broadcast::{self, Receiver}}, time};
use anyhow::Result;

use crate::PeerTx;

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

    pub async fn add(&self, client_tx: PeerTx) {
        let notify_rx = self.notifier.subscribe();

        async fn forward_notifications(client_tx: PeerTx, mut notify_rx: Receiver<LapasProtocol>) -> Result<()> {
            loop {
                tokio::select! {
                    notification = notify_rx.recv() => {
                        let notification = notification?;
                        client_tx.send(notification).await?;
                    },
                    _ = time::sleep(Duration::from_millis(1000)) => {
                        client_tx.send(LapasProtocol::ControlPing).await?;
                    }
                };
            }
        }

        tokio::spawn(forward_notifications(client_tx, notify_rx));
    }
}