#!/bin/bash

if [ "$USER" != "root" ]; then
        echo "You have to be logged in as root to use this. Hint: use 'su - root' instead of su root"; exit 1;
fi

# import LAPAS config
. $(dirname "$0")/config;

##########################################################################

kernelVersion="$1";

if [ "$#" != "1" ]; then
        echo "Usage: $0 <KERNEL_VERSION>"
        exit 1;
fi

##########################################################################

pushd "${LAPAS_GUESTROOT_DIR}/usr/src/";

rm "./linux-${kernelVersion}/.config";

# find newest currently installed kernel with a .config file
newestInstalledPath=$(find "." -maxdepth 1 -type d -name "linux-*" -exec test -f "{}/.config" \; -print | sort --version-sort -r | head -n1);

# download new version
wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${kernelVersion}.tar.xz" || exit 1
tar xvf "./linux-${kernelVersion}.tar.xz" || exit 1;
rm "./linux-${kernelVersion}.tar.xz" || exit 1;

# copy over config from previous version and open config editor
if [ -n "$newestInstalledPath" ] && [ -d "$newestInstalledPath" ]; then
        echo "Copying config file from previous version: $newestInstalledPath";
        cp "${newestInstalledPath}/.config" "./linux-${kernelVersion}/" || exit 1;
        "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /usr/src/linux-${kernelVersion} && make oldconfig";
else
        "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /usr/src/linux-${kernelVersion} && make menuconfig";
fi

# build new kernel
pushd "./linux-${kernelVersion}";
echo "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}";
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /usr/src/linux-${kernelVersion} && make -j$(nproc) | tee /tmp/kernel_build.log" || exit 1;
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /usr/src/linux-${kernelVersion} && make modules_install" || exit 1;
popd;

# update bootmenu
echo "####################";
echo "Updating bootmenu...";
"${LAPAS_SCRIPTS_DIR}/updateBootmenus.sh" || exit $?