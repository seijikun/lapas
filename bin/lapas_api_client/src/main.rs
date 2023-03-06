mod daemon;

use anyhow::{anyhow, Result, Context};
use tokio::{net::TcpStream, io::AsyncWriteExt};
use lapas_api_proto::{LapasProtocol, ProtoSerde, ApiAuth};
use clap::{Parser, Subcommand};

macro_rules! perform_request {
    ($connection:expr, $response_pkt:ident = $req_pkt:expr) => {
        {
            $req_pkt.encode($connection).await?;
            let response = LapasProtocol::decode($connection).await?;
            if let LapasProtocol::$response_pkt { result } = response {
                result
            } else {
                return Err(anyhow!("Received unexpected response"));
            }
        }
    };
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
    },
    /// Display a list of all registered players
    ListUsers
}

fn args_to_auth(args: &CliArgs) -> Result<ApiAuth> {
    // use one of the supplied authentication mechanisms (prefer root_nonce).
    match (&args.api_password, &args.root_nonce) {
        (_, Some(root_nonce)) => Ok(ApiAuth::RootNonce(root_nonce.clone())),
        (Some(api_password), _) => Ok(ApiAuth::Password(api_password.clone())),
        _ => Err(anyhow!("This action requires authentication"))
    }
}

async fn lapas_connect(args: &CliArgs) -> Result<TcpStream> {
    let mut stream = TcpStream::connect(format!("{}:{}", args.api_host, args.api_port)).await?;
    LapasProtocol::ControlHandshake { version: lapas_api_proto::VERSION }.encode(&mut stream).await?;

    let response = LapasProtocol::decode(&mut stream).await?;
    match response {
        LapasProtocol::ControlHandshakeResponse { result } => {
            match result {
                Ok(_) => Ok(stream),
                Err(e) => Err(anyhow!("Conncting to lapas api server failed: {}", e))
            }
        },
        _ => Err(anyhow!("Received unexpected response"))
    }
}


async fn cmd_check_auth(args: &CliArgs, connection: &mut TcpStream) -> Result<()> {
    let result = perform_request!(connection, ControlCheckAuthResponse = LapasProtocol::ControlCheckAuth { auth: args_to_auth(args)? });
    result
        .map_err(|e| anyhow!(e))
        .context("Checking API authentication")?;
    println!("Authentication Successful");
    Ok(())
}

async fn cmd_add_dns_mapping(args: &CliArgs, connection: &mut TcpStream, username: &str) -> Result<()> {
    let auth = args_to_auth(args)?;
    let result = perform_request!(connection,
        UserDnsMappingResponse = LapasProtocol::UserDnsMapping { auth, username: username.to_owned() });
    result
        .map_err(|e| anyhow!(e))
        .context("Adding DNS Mapping for this machine")?;
    println!("DNS Mapping for user: {} to this device successfully created", username);
    Ok(())
}

async fn cmd_add_user(args: &CliArgs, connection: &mut TcpStream, username: &str, password: &str) -> Result<()> {
    let auth = args_to_auth(args)?;
    let (new_username, new_password) = (username.to_owned(), password.to_owned());
    let result = perform_request!(connection,
        UserRegisterResponse = LapasProtocol::UserRegister { auth, new_username, new_password });
    result
        .map_err(|e| anyhow!(e))
        .context("Registering new user")?;
    println!("User: {} was successfully created", username);
    Ok(())
}

async fn cmd_list_users(connection: &mut TcpStream) -> Result<()> {
    let mut users = perform_request!(connection, PasswdGetListResponse = LapasProtocol::PasswdGetList)
        .map_err(|e| anyhow!(e))
        .context("Acquiring list of registered users")?;
    users.sort_by_key(|u| u.id);
    for user in users {
        println!("{}: {}", user.id, user.name);
    }
    Ok(())
}


#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args = CliArgs::parse();
    if let (None, None) = (&args.api_password, &args.root_nonce) {
        return Err(anyhow!("Authentication option required"));
    }

    if let ClientCommand::Daemon = &args.command {
        daemon::run(&args).await
    } else {
        let mut connection = lapas_connect(&args).await?;
        let result = match &args.command {
            ClientCommand::CheckAuth => cmd_check_auth(&args, &mut connection).await,
            ClientCommand::AddDnsMapping { username } => cmd_add_dns_mapping(&args, &mut connection, username).await,
            ClientCommand::AddUser { username, password } => cmd_add_user(&args, &mut connection, username, password).await,
            ClientCommand::ListUsers => cmd_list_users(&mut connection).await,
            _ => unreachable!()
        };
        let _ = connection.shutdown().await;
        result
    }
}
