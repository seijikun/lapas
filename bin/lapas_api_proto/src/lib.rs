pub mod proto;
pub use proto::*;

pub type Version = u32;
pub const VERSION: Version = 2;

define_protocol!(proto LapasProtocol {
    ResponseResult {
        result: Result<(), String>
    },

    RequestHello {
        version: Version,
        password: Option<String>
    },
    RequestPing {},
    RequestAddUser {
        username: String,
        password: String
    },

    // switch to notify mode. After sending this package (client -> server), the
    // connection can only be used to receive notifications from the server
    SwitchNotify {},
    NotifyRootChanged {}
});