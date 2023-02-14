mod daemon;

use anyhow::{anyhow, Result, Context};
use tokio::{net::TcpStream, io::{AsyncWriteExt, AsyncReadExt}};
use lapas_api_proto::{LapasProtocol, ProtoSerde, ApiPassword};
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

    /// Root Nonce to use for authentication with the LAPAS API server.
    #[arg(long = "rootauth", env)]
    root_nonce: Option<String>,

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
    /// Add a DNS mapping for the IP of this machine to the given username
    AddDnsMapping {
        username: String
    },
    /// Add a new player user with the given credentials (username & password).
    AddUser {
        username: String,
        password: String
    }
}

async fn connect_and_authenticate(args: &CliArgs) -> Result<TcpStream> {
    let mut stream = TcpStream::connect(format!("{}:{}", args.api_host, args.api_port)).await?;
    // use one of the supplied authentication mechanisms (prefer root_nonce).
    let password = match (&args.api_password, &args.root_nonce) {
        (_, Some(root_nonce)) => ApiPassword::RootNonce(root_nonce.clone()),
        (Some(api_password), _) => ApiPassword::Plain(api_password.clone()),
        _ => unreachable!()
    };
    perform_request(
        &mut stream,
        LapasProtocol::RequestHello { version: lapas_api_proto::VERSION, password }
    ).await.context("Login")?.map_err(|msg| anyhow!(msg))?;
    Ok(stream)
}


async fn cmd_check_auth(args: &CliArgs) -> Result<()> {
    let mut connection = connect_and_authenticate(args).await?;
    let _ = connection.shutdown().await;
    println!("Authentication Successful");
    Ok(())
}

async fn cmd_add_dns_mapping(args: &CliArgs, username: &str) -> Result<()> {
    let mut connection = connect_and_authenticate(args).await?;
    perform_request(
        &mut connection,
        LapasProtocol::RequestDnsMapping { username: username.to_owned() }
    ).await?.map_err(|e| anyhow!(e)).context("Adding DNS Mapping for this machine failed")?;
    println!("DNS Mapping for user: {} to this device successfully created", username);
    Ok(())
}

async fn cmd_add_user(args: &CliArgs, username: &str, password: &str) -> Result<()> {
    let mut connection = connect_and_authenticate(args).await?;
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
    if let (None, None) = (&args.api_password, &args.root_nonce) {
        return Err(anyhow!("Authentication option required"));
    }

    match &args.command {
        ClientCommand::Daemon => daemon::run(&args).await?,
        ClientCommand::CheckAuth => cmd_check_auth(&args).await?,
        ClientCommand::AddDnsMapping { username } => cmd_add_dns_mapping(&args, username).await?,
        ClientCommand::AddUser { username, password } => cmd_add_user(&args, username, password).await?,
    }
    Ok(())
}
