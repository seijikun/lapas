use anyhow::{Result, anyhow};
use lapas_api_proto::{LapasProtocol, ApiAuth, ProtoSerde, LapasUserShadow, LapasUserPasswd};
use tokio::{net::UnixStream, fs::File, io::BufReader, io::AsyncBufReadExt};

const SERVICE_ENVFILE_PATH: &'static str = "/lapas/lapas-api.env";
const LAPAS_AUTH_SOCKET: &'static str = "/run/lapas/auth_serv.socket";

async fn get_api_password() -> Result<String> {
    let service_env_file = File::open(SERVICE_ENVFILE_PATH).await?;
    let service_env_reader = BufReader::new(service_env_file);
    let mut service_env_lines = service_env_reader.lines();
    while let Some(line) = service_env_lines.next_line().await? {
        if line.starts_with("API_PASSWORD=\"") && line.ends_with("\"") {
            return Ok(line[14..line.len()-1].to_string())
        }
    }
    Err(anyhow!("Failed to parse lapas-api environment file!"))
}

async fn lapas_connect() -> Result<UnixStream> {
    let mut stream = UnixStream::connect(LAPAS_AUTH_SOCKET).await?;
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

pub fn passwd_list() -> Result<Vec<LapasUserPasswd>> {
    let async_rt = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .build()
        .expect("Failed to initialize tokio async runtime");

    async_rt.block_on(async move {
        let mut connection = lapas_connect().await?;

        LapasProtocol::PasswdGetList.encode(&mut connection).await?;
        let response = LapasProtocol::decode(&mut connection).await?;
        if let LapasProtocol::PasswdGetListResponse { result } = response {
            match result {
                Ok(users) => Ok(users),
                Err(e) => Err(anyhow!("Error while getting passwd list from lapas: {}", e))
            }
        } else {
            Err(anyhow!("Received unexpected response from server"))
        }
    })
}

pub fn shadow_list() -> Result<Vec<LapasUserShadow>> {
    let async_rt = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .build()
        .expect("Failed to initialize tokio async runtime");

    async_rt.block_on(async move {
        let mut connection = lapas_connect().await?;

        let auth = ApiAuth::Password(get_api_password().await?);
        LapasProtocol::ShadowGetList{ auth }.encode(&mut connection).await?;
        let response = LapasProtocol::decode(&mut connection).await?;
        if let LapasProtocol::ShadowGetListResponse { result } = response {
            match result {
                Ok(users) => Ok(users),
                Err(e) => Err(anyhow!("Error while getting shadow list from lapas: {}", e))
            }
        } else {
            Err(anyhow!("Received unexpected response from server"))
        }
    })
}
