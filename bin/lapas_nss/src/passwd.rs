use lapas_api_proto::LapasUserPasswd;
use libnss::{passwd::{PasswdHooks, Passwd}, interop::Response, libnss_passwd_hooks};
use crate::api;


fn user_to_passwd(user: LapasUserPasswd) -> Passwd {
    Passwd {
        name: user.name.clone(),
        passwd: "x".to_string(),
        uid: user.id as u32,
        gid: 1000,
        gecos: user.name.clone(),
        dir: format!("/home/{}", user.name),
        shell: "/bin/bash".to_string()
    }
}


struct LapasPasswd;
libnss_passwd_hooks!(lapas, LapasPasswd);

// Creates an account with username "test", and password "pass"
// Ensure the home directory "/home/test" exists, and is owned by 1007:1007
impl PasswdHooks for LapasPasswd {
    fn get_all_entries() -> Response<Vec<Passwd>> {
        match api::passwd_list() {
            Ok(users) => {
                Response::Success(
                    users.into_iter()
                        .map(|user| user_to_passwd(user))
                        .collect()
                )
            },
            Err(e) => {
                eprintln!("Lapas api server NSS lookup failed: {}", e);
                Response::Unavail
            }
        }
    }

    fn get_entry_by_uid(uid: libc::uid_t) -> Response<Passwd> {
        let user_list = api::passwd_list();
        if let Err(e) = user_list {
            eprintln!("Lapas api server NSS lookup failed: {}", e);
            return Response::Unavail;
        }

        if let Some(user) = user_list.unwrap().into_iter().find(|u| u.id == uid as u64) {
            return Response::Success(user_to_passwd(user));
        }

        Response::NotFound
    }

    fn get_entry_by_name(name: String) -> Response<Passwd> {
        let user_list = api::passwd_list();
        if let Err(e) = user_list {
            eprintln!("Lapas api server NSS lookup failed: {}", e);
            return Response::Unavail;
        }

        if let Some(user) = user_list.unwrap().into_iter().find(|u| u.name == name) {
            return Response::Success(user_to_passwd(user));
        }

        Response::NotFound
    }
}