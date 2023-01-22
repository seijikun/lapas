#!/bin/bash
if [ "$USER" != "root" ]; then
	echo "You have to be logged in as root to use this. Hint: use 'su - root' instead of su root"; exit 1;
fi

# import LAPAS config
. $(dirname "$0")/config;

userName="$1";
password="$2";
if [ "$userName" == "" ];then
	echo "Usage: $0 <userName> [<password>]"; exit 1;
fi

cd "${LAPAS_GUESTROOT_DIR}" || exit 1;
./bin/arch-chroot ./ useradd -d "/home/${userName}" -g lanparty -M -o -u 1000 "$userName" || exit $?;
if [ "$password" != "" ]; then
	yes "$password" | ./bin/arch-chroot ./ passwd "$userName" || exit $?;
else
	./bin/arch-chroot ./ passwd "$userName" || exit $?;
fi
echo "User created successfully."