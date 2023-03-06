pub mod proto;
pub mod models;

pub use proto::*;
pub use models::*;

pub type Version = u32;
pub const VERSION: Version = 6;


define_protocol!(proto LapasProtocol {
    // # Control Packets
    // ####################
    // Version comparison with server
    ControlHandshake { version: Version },
    ControlHandshakeResponse { result: Result<(), String> },
    // For long-running connections, this is used to notice early on when the tcp
    // connection crashed (doesn't have a response, both client and server send this regularly)
    ControlPing,
    // Register for server notifications
    ControlListenEvents,

    // Ask server to test the supplied authentication
    ControlCheckAuth { auth: ApiAuth },
    ControlCheckAuthResponse { result: Result<(), String> },

    // # User Packets
    // ####################
    // Register a new user
    // - Requires auth
    UserRegister {
        auth: ApiAuth,
        new_username: String,
        new_password: String
    },
    UserRegisterResponse { result: Result<(), String> },

    // Tell the server that he should now create a dns mapping for the given user
    // to the ip address from which this requests is comming
    // - Requires auth
    UserDnsMapping {
        auth: ApiAuth,
        username: String
    },
    UserDnsMappingResponse { result: Result<(), String> },

    // Passwd get listing
    PasswdGetList,
    PasswdGetListResponse { result: Result<Vec<LapasUserPasswd>, String> },

    // Shadow get listing
    ShadowGetList { auth: ApiAuth },
    ShadowGetListResponse { result: Result<Vec<LapasUserShadow>, String> },


    // # Event Packets
    // ####################
    // Packet notifying guests that they should remount their root filesystem because
    // some files have changed (takes a remount to avoid stale file handle errors with overlayfs)
    NotifyRootChanged,
    // Packet notifying guests that they should now clear their dns cache because some
    // mappings have changed
    NotifyDnsMappingsChanged,
    // Packet notifying guests that the list of registered users has changed
    NotifyUsersChanged
});