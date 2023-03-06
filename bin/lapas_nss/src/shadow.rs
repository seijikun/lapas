use chrono::Duration;
use lapas_api_proto::LapasUserShadow;
use libnss::{libnss_shadow_hooks, shadow::{ShadowHooks, Shadow}, interop::Response};

use crate::api;


fn user_to_shadow(user: LapasUserShadow) -> Shadow {
    let last_update_days_since_unix = Duration::seconds(user.last_update_ts.timestamp()).num_days();
    Shadow {
        name: user.name,
        passwd: user.password_hash,
        last_change: last_update_days_since_unix,
        change_min_days: 0,
        change_max_days: 99999,
        change_warn_days: 7,
        change_inactive_days: -1,
        expire_date: -1,
        reserved: 0
    }
}


struct LapasShadow;
libnss_shadow_hooks!(lapas, LapasShadow);

impl ShadowHooks for LapasShadow {
    fn get_all_entries() -> Response<Vec<Shadow>> {
        match api::shadow_list() {
            Ok(users) => {
                Response::Success(
                    users.into_iter()
                        .map(|user| user_to_shadow(user))
                        .collect()
                )
            },
            Err(e) => {
                eprintln!("Lapas api server NSS lookup failed: {}", e);
                Response::Unavail
            }
        }
    }

    fn get_entry_by_name(name: String) -> Response<Shadow> {
        let user_list = api::shadow_list();
        if let Err(e) = user_list {
            eprintln!("Lapas api server NSS lookup failed: {}", e);
            return Response::Unavail;
        }

        if let Some(user) = user_list.unwrap().into_iter().find(|u| u.name == name) {
            return Response::Success(user_to_shadow(user));
        }

        Response::NotFound
    }
}