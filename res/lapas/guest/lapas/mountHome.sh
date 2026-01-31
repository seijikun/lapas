#!/bin/bash

# Constants
BASEUSER_NAME="lapas";
BASEUSER_UID=$(id -u "$BASEUSER_NAME"); # lapas uid
BASEUSER_GID=$(id -g "$BASEUSER_NAME"); # lanparty gid
USER_IMAGE_SIZE="16G";
USER_IMAGE_BASE="/mnt/homes";
USER_MOUNT_BASE="/mnt/.mounts";
USER_BASE_DIR="/mnt/homeBase";

# import lapas config
. "/lapas/common.sh" || exit 1;
. "/lapas/lapas-api.env" || exit 1;

# get uid/gid of user
LOGINUSER_UID=$(id -u "$PAM_USER");
LOGINUSER_GID=$(id -g "$PAM_USER");
LOGINUSER_HOME=$(getent passwd "$PAM_USER" | cut -d: -f6);

# Only run mountHome-script for lapas users
[ "$LOGINUSER_GID" != "$BASEUSER_GID" ] && exit 0;

if [[ ! -f "/.lapasUser" && "$PAM_USER" != "$BASEUSER_NAME" ]]; then
        >&2 echo "In Admin mode, only ${BASEUSER_NAME} can login"
        exit 1;
fi

echo "[LOGON] Login user: ${PAM_USER}, home: ${LOGINUSER_HOME}";

if [ "$PAM_USER" != "$BASEUSER_NAME" ] && [ "$PAM_TYPE" == "open_session" ]; then
        echo "[LOGON] Detected normal user";
        API_PASSWORD="${API_PASSWORD}" /lapas/lapas-api-client add-dns-mapping "${PAM_USER}";

        USER_MOUNT_DIR="${USER_MOUNT_BASE}/${PAM_USER}";
        USER_PERSISTENT_MOUNT_DIR="${USER_MOUNT_DIR}/overlay"; # contains mounted user ext4 image
        USER_BASE_MOUNT_DIR="${USER_MOUNT_DIR}/base"; # contains a bindmount pointing to /mnt/homeBase but idmapped to user
        USER_PERSISTENT_IMAGE="${USER_IMAGE_BASE}/${PAM_USER}";

        # create and format user persistence (ext4) image if it doesn't exist yet
        if [ ! -f "$USER_PERSISTENT_IMAGE" ]; then
                # create image for user-specific dynamic data
                assertSuccessfull truncate -s $USER_IMAGE_SIZE "$USER_PERSISTENT_IMAGE";
                assertSuccessfull mkfs.ext4 -m0 "$USER_PERSISTENT_IMAGE" 1> /dev/null 2> /dev/null;
        fi

        # mount /mnt/homeBase idmapped for the user that is currently logging in
        # TODO: switch to kernel built-in idmapping as soon as NFS is supported
        if [ $(mount | grep "$USER_BASE_MOUNT_DIR" | wc -l) == 0 ]; then
                # create user-specific/idmapped mount-point for homeBase
                assertSuccessfull mkdir -p "$USER_BASE_MOUNT_DIR";
                assertSuccessfull bindfs --map=${BASEUSER_UID}/${LOGINUSER_UID} -o ro,noatime,kernel_cache,entry_timeout=3600,attr_timeout=3600,negative_timeout=3600 --multithreaded "$USER_BASE_DIR" "$USER_BASE_MOUNT_DIR";
        fi

        if [ $(mount | grep "$USER_PERSISTENT_IMAGE" | wc -l) == 0 ]; then
                # create user-specific work folder
                assertSuccessfull mkdir -p "$USER_PERSISTENT_MOUNT_DIR";
                # mount user-image
                assertSuccessfull mount "$USER_PERSISTENT_IMAGE" "$USER_PERSISTENT_MOUNT_DIR";
                assertSuccessfull mkdir -p "$USER_PERSISTENT_MOUNT_DIR/upper";
                assertSuccessfull mkdir -p "$USER_PERSISTENT_MOUNT_DIR/work";
                assertSuccessfull chown -R $PAM_USER:lanparty "$USER_PERSISTENT_MOUNT_DIR";
                # remove cleanup marker from user's upper dir on every mount (once per boot)
                if [ -f "${USER_PERSISTENT_MOUNT_DIR}/upper/.keepApplied" ]; then
                        rm "${USER_PERSISTENT_MOUNT_DIR}/upper/.keepApplied";
                fi
        fi
        if [ ! -f "${USER_PERSISTENT_MOUNT_DIR}/upper/.keepApplied" ]; then
                # Cleanup has not yet run on this boot, run it now
                assertSuccessfull "/lapas/keepEngine" user "${USER_BASE_MOUNT_DIR}/.keep" "${USER_PERSISTENT_MOUNT_DIR}/upper";
                # if cleanup ran successfully, create a temporary marker file .keepApplied that will be
                # deleted upon next home mount (after a reboot).
                touch "${USER_PERSISTENT_MOUNT_DIR}/upper/.keepApplied";
        fi
        if [ $(mount | grep "$LOGINUSER_HOME" | wc -l) == 0 ]; then
                assertSuccessfull mkdir -p "$LOGINUSER_HOME";
                assertSuccessfull chown -R $PAM_USER:lanparty "$LOGINUSER_HOME";
                assertSuccessfull mount -t overlay overlay -o lowerdir="${USER_BASE_MOUNT_DIR}",upperdir="${USER_PERSISTENT_MOUNT_DIR}/upper",workdir="${USER_PERSISTENT_MOUNT_DIR}/work" "$LOGINUSER_HOME";
        fi
fi
