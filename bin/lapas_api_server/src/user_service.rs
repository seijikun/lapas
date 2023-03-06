use std::{path::{PathBuf, Path}, os::unix::prelude::PermissionsExt};
use chrono::{DateTime, Utc};
use lapas_api_proto::{UserId, LapasUserPasswd, LapasUserShadow};
use rand::{distributions::Alphanumeric, Rng};
use serde::{Serialize, Deserialize};
use sha_crypt::{Sha512Params, sha512_crypt_b64};
use tokio::{fs::File, io::{AsyncReadExt, AsyncWriteExt}, sync::Mutex};

use anyhow::{anyhow, Result};

#[derive(Serialize, Deserialize)]
struct UserIndexEntry {
    id: UserId,
    name: String,
    password_hash: String,
    creation_ts: DateTime<Utc>,
    last_update_ts: DateTime<Utc>
}

#[derive(Serialize, Deserialize)]
struct UserIndex {
    next_id: UserId,
    users: Vec<UserIndexEntry>
}
impl Default for UserIndex {
    fn default() -> Self {
        Self { next_id: 10000, users: vec![] }
    }
}


async fn read_user_index(path: &Path) -> Result<UserIndex> {
    if !path.exists() {
        return Ok(Default::default())
    }
    let mut file = File::open(path).await?;
    let mut file_data = String::new();
    file.read_to_string(&mut file_data).await?;

    Ok(serde_json::from_str(&file_data)?)
}

async fn write_user_index(path: &Path, index: &UserIndex) -> Result<()> {
    let mut file = File::create(path).await?;
    let file_data = serde_json::to_string_pretty(&index)?;
    file.write_all(file_data.as_bytes()).await?;

    // fix file permissions
    let mut index_file_permissions = file.metadata().await?.permissions();
    index_file_permissions.set_mode(0);
    file.set_permissions(index_file_permissions).await?;

    Ok(())
}

fn password_to_ghost_random_salt(password: &str) -> String {
    let params = Sha512Params::new(5000).expect("Failed to initialize password hasher");

    let salt: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(16)
        .map(char::from)
        .collect();

    let hashed_password = sha512_crypt_b64(password.as_bytes(), salt.as_bytes(), &params)
        .expect("Failed to create crypted password hash");
    format!("$6${}${}", salt, hashed_password)
}



pub(crate) struct UserService {
    user_index_path: PathBuf,
    user_index: Mutex<UserIndex>
}
impl UserService {
    pub async fn new(homes_dir: String) -> Result<Self> {
        let mut user_index_path = PathBuf::from(homes_dir);
        user_index_path.push("USER_INDEX");

        let user_index = read_user_index(&user_index_path).await?;

        Ok(Self {
            user_index_path,
            user_index: Mutex::new(user_index)
        })
    }

    pub async fn add_user(&self, username: String, password: String) -> Result<()> {
        let mut user_index = self.user_index.lock().await;

        // validation
        if username.len() < 3 { return Err(anyhow!("Username too short!")); }

        let username_taken = user_index.users.iter().find(|user| user.name == username).is_some();
        if username_taken { return Err(anyhow!("User with the requested name already exists!")); }

        if password.len() == 0 { return Err(anyhow!("Password must not be empty!")); }

        // add user
        let new_user = UserIndexEntry {
            id: user_index.next_id,
            name: username,
            password_hash: password_to_ghost_random_salt(&password),
            creation_ts: Utc::now(),
            last_update_ts: Utc::now()
        };

        user_index.users.push(new_user);
        user_index.next_id += 1;

        write_user_index(&self.user_index_path, &user_index).await?;

        Ok(())
    }

    pub async fn passwd_all(&self) -> Result<Vec<LapasUserPasswd>> {
        let user_index = self.user_index.lock().await;
        Ok(user_index.users.iter()
            .map(|usr| LapasUserPasswd {
                id: usr.id,
                name: usr.name.clone()
            })
            .collect()
        )
    }

    pub async fn shadow_all(&self) -> Result<Vec<LapasUserShadow>> {
        let user_index = self.user_index.lock().await;
        Ok(user_index.users.iter()
            .map(|usr| LapasUserShadow {
                id: usr.id,
                name: usr.name.clone(),
                password_hash: usr.password_hash.clone(),
                last_update_ts: usr.last_update_ts
            })
            .collect()
        )
    }

}