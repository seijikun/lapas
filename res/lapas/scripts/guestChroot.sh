#!/bin/bash
if [ "$USER" != "root" ]; then
	echo "You have to be logged in as root to use this. Hint: use 'su - root' instead of su root"; exit 1;
fi

# import LAPAS config
. $(dirname "$0")/config;

cd "${LAPAS_GUESTROOT_DIR}" || exit 1;
echo "Entering chroot now..";
./bin/arch-chroot ./;