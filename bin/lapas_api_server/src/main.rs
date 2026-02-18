use std::{path::PathBuf, sync::Arc};
use anyhow::Result;
use clap::Parser;

use crate::state::State;

mod api_services;
mod api_server;
mod state;

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
    let state = Arc::new(State::init(&args.config_file).await?);

    api_server::run(state.clone()).await?;

    Ok(())
}
