mod daemon;

use anyhow::{anyhow, Result, Context};
use tokio::{net::TcpStream, io::{AsyncWriteExt, AsyncReadExt}};
use lapas_api_proto::{LapasProtocol, ProtoSerde};
use clap::{Parser, Subcommand};

//TODO: improve error handling with thiserror instead of anyhow? (different return values for different errors)

async fn perform_request<W: AsyncReadExt + AsyncWriteExt + Send + Unpin>(stream: &mut W, request: LapasProtocol) -> Result<std::result::Result<(), String>> {
    request.encode(stream).await?;
    let response = LapasProtocol::decode(stream).await?;
    if let LapasProtocol::ResponseResult { result } = response {
        Ok(result)
    } else {
        Err(anyhow!("Received unexpected packet"))
    }
}


/// LAPAS API client
#[derive(Debug, Parser)]
#[command(name = "lapas_api_server")]
#[command(author, version, about)]
struct CliArgs {
    /// LAPAS administration password to use during authentication with the API server.
    #[arg(long = "auth")]
    api_password: Option<String>,

    /// Address of the LAPAS pi server
    #[arg(long = "host", default_value = "lapas")]
    api_host: String,

    /// Port of the LAPAS api server
    #[arg(long = "port", default_value_t = 1337)]
    api_port: u16,

    #[command(subcommand)]
    command: ClientCommand
}

#[derive(Debug, Subcommand)]
enum ClientCommand {
    /// Start a lapas api client daemon.
    /// This daemon registers for notifications from the LAPAS api server and responds
    /// to them. (e.g. by remounting the root filesystem if required).
    Daemon,
    /// Connect to the LAPAS API server and check whether the given administration password
    /// is correct. Returns process exit code 0 if successfull, with a code != 0 otherwise.
    CheckAuth,
    /// Add a new player user with the given credentials (username & password).
    AddUser {
        username: String,
        password: String
    }
}

async fn connect(args: &CliArgs) -> Result<TcpStream> {
    let mut stream = TcpStream::connect(format!("{}:{}", args.api_host, args.api_port)).await?;
    perform_request(
        &mut stream,
        LapasProtocol::RequestHello { version: lapas_api_proto::VERSION, password: args.api_password.clone() }
    ).await.context("Login")?.map_err(|msg| anyhow!(msg))?;
    Ok(stream)
}


async fn cmd_check_auth(args: &CliArgs) -> Result<()> {
    if args.api_password.is_none() {
        return Err(anyhow!("You have to pass the authentication password to use this command"));
    }
    let mut connection = connect(args).await?;
    let _ = connection.shutdown().await;
    println!("Authentication Successful");
    Ok(())
}


async fn cmd_add_user(args: &CliArgs, username: &str, password: &str) -> Result<()> {
    let mut connection = connect(args).await?;
    perform_request(
        &mut connection,
        LapasProtocol::RequestAddUser { username: username.to_owned(), password: password.to_owned() }
    ).await?.map_err(|e| anyhow!(e)).context("Adding user failed")?;
    println!("User: {} was successfully created", username);
    Ok(())
}


#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args = CliArgs::parse();

    match &args.command {
        ClientCommand::Daemon => daemon::run(&args).await?,
        ClientCommand::CheckAuth => cmd_check_auth(&args).await?,
        ClientCommand::AddUser { username, password } => cmd_add_user(&args, username, password).await?,
    }
    Ok(())
}
