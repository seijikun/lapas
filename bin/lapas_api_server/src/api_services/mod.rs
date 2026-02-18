use std::{ops::DerefMut as _, sync::Arc};

use anyhow::Result;
use lapas_api_proto::{LapasProtocol, ProtoSerde as _};
use tokio::{io::AsyncWriteExt as _, net::tcp::{OwnedReadHalf, OwnedWriteHalf}, sync::Mutex};

pub mod dns;
pub mod notification;
pub mod user;


#[derive(Clone)]
pub struct PeerTx {
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

pub struct PeerRx {
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