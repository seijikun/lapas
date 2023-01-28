#!/bin/bash
if [ "$USER" != "root" ]; then
	echo "You have to be logged in as root to use this. Hint: use 'su - root' instead of su root"; exit 1;
fi

# import LAPAS config
. $(dirname "$0")/config;
# KERNEL-CMDLINE
GUEST_USER_OPTIONS="ip=dhcp carrier_timeout=10";
GUEST_ADMIN_OPTIONS="ip=dhcp carrier_timeout=10 root=/dev/nfs rw nfsroot=${LAPAS_NET_IP}:/guest,vers=${LAPAS_NFS_VERSION}";

################################################################################################

echo "Deleting old deployed kernels..."
find "${LAPAS_TFTP_DIR}/boot" -type f -name "bzImage*" -delete;

echo "Deploying current ramdisk...";
cp "${LAPAS_GUESTROOT_DIR}/boot/ramdisk.img" "${LAPAS_TFTP_DIR}/boot/";

# Empty out grub.cfg file
cat <<"EOF" > "${LAPAS_TFTP_DIR}/grub2/grub.cfg"
set default="0"
set timeout=5

EOF


# Call this method for every kernel to add it to the newly generated boot menu
# Usage: addKernelToBootMenu <absolutePathToGuestKernel>
function addKernelToBootMenu() {
	kernelDir="$1";
	kernelName=$(basename "$kernelDir");
	kernelVersion="${kernelName#linux-*}";
	kernelBinPath="${kernelDir}/arch/x86_64/boot/bzImage";
	if [ ! -f "${kernelBinPath}" ]; then return 0; fi
	echo "Adding ${kernelName} to bootmenus...";
	cp "${kernelBinPath}" "${LAPAS_TFTP_DIR}/boot/bzImage-${kernelVersion}";
	cat <<EOF >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg"
#############################################################################
menuentry 'User-${kernelVersion}' {
	linux /boot/bzImage-${kernelVersion} ${GUEST_USER_OPTIONS} init=/lib/systemd/systemd
	initrd /boot/ramdisk.img
}
menuentry 'Admin-${kernelVersion}' {
	linux /boot/bzImage-${kernelVersion} ${GUEST_ADMIN_OPTIONS} init=/lib/systemd/systemd
}

EOF
}

while read -r kernelDir; do
	addKernelToBootMenu "$kernelDir";
done <<< $(find "${LAPAS_GUESTROOT_DIR}/usr/src/" -type d -name "linux-*" | sort --version-sort -r);

chmod a+r -R "${LAPAS_TFTP_DIR}/boot";
