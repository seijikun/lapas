#!/bin/bash

# Constants
USER_IMAGE_SIZE="16G";
USER_IMAGE_BASE="/mnt/homes";
USER_WORKDIR_BASE="/mnt/.overlays";
USER_BASE="/mnt/homeBase";
LAPAS_USER_GROUPNAME="lanparty";

. /lapas/common.sh || exit 1;

# Only run mountHome-script for lapas users
[ $(id -ng $PAM_USER) != "$LAPAS_USER_GROUPNAME" ] && exit 0;

if [[ ! -f "/.lapasUser" && "$PAM_USER" != "lapas" ]]; then
	>&2 echo "In Admin mode, only lapas can login"
	exit 1;
fi

USER_HOME=$(getent passwd $PAM_USER | cut -d: -f6);
echo "[LOGON] Login user: $PAM_USER, home: $USER_HOME";

if [ "$PAM_USER" != "lapas" ] && [ "$PAM_TYPE" == "open_session" ]; then
	echo "[LOGON] Detected normal user";
	USER_IMAGE="${USER_IMAGE_BASE}/${PAM_USER}";
	USER_IMAGE_MOUNTDIR="${USER_WORKDIR_BASE}/${PAM_USER}";

	if [ ! -f "$USER_IMAGE" ]; then
		# create image for user-specific dynamic data
		assertSuccessfull truncate -s $USER_IMAGE_SIZE "$USER_IMAGE";
		assertSuccessfull mkfs.ext4 -m0 "$USER_IMAGE" 1> /dev/null 2> /dev/null;
	fi
	if [ $(mount | grep "$USER_IMAGE" | wc -l) == 0 ]; then
		# create user-specific work folder
		assertSuccessfull mkdir -p "$USER_IMAGE_MOUNTDIR";
		# mount user-image
		assertSuccessfull mount "$USER_IMAGE" "$USER_IMAGE_MOUNTDIR";
		assertSuccessfull mkdir -p "$USER_IMAGE_MOUNTDIR/upper";
		assertSuccessfull mkdir -p "$USER_IMAGE_MOUNTDIR/work";
		assertSuccessfull chown -R $PAM_USER:lanparty "$USER_IMAGE_MOUNTDIR";
		# remove cleanup marker from user's upper dir on every mount (once per boot)
		if [ -f "${USER_IMAGE_MOUNTDIR}/upper/.keepApplied" ]; then
			rm "${USER_IMAGE_MOUNTDIR}/upper/.keepApplied";
		fi
	fi
	if [ ! -f "${USER_IMAGE_MOUNTDIR}/upper/.keepApplied" ]; then
		# Cleanup has not yet run on this boot, run it now
		"/lapas/keepEngine" user "${USER_BASE}/.keep" "${USER_IMAGE_MOUNTDIR}/upper" || exit 1;
		# if cleanup ran successfully, create a temporary marker file .keepApplied that will be
		# deleted upon next home mount (after a reboot).
		touch "${USER_IMAGE_MOUNTDIR}/upper/.keepApplied";
	fi
	if [ $(mount | grep "$USER_HOME" | wc -l) == 0 ]; then
		assertSuccessfull mkdir -p "$USER_HOME";
		assertSuccessfull chown -R $PAM_USER:lanparty "$USER_HOME";
		assertSuccessfull mount -t overlay overlay -o lowerdir="${USER_BASE}",upperdir="${USER_IMAGE_MOUNTDIR}/upper",workdir="${USER_IMAGE_MOUNTDIR}/work" "$USER_HOME";
	fi
fi
