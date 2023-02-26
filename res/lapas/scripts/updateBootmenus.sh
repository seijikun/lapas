#!/bin/bash
if [ "$USER" != "root" ]; then
	echo "You have to be logged in as root to use this. Hint: use 'su - root' instead of su root"; exit 1;
fi

# import LAPAS config
. $(dirname "$0")/config;
# KERNEL-CMDLINE
GUEST_USER_OPTIONS="ip=dhcp carrier_timeout=10 lapas_mode=user";
GUEST_ADMIN_OPTIONS="ip=dhcp carrier_timeout=10 lapas_mode=admin";

################################################################################################

# Empty out grub.cfg file
cat <<"EOF" > "${LAPAS_TFTP_DIR}/grub2/grub.cfg"
### BEGIN /etc/grub.d/00_header ###
loadfont "unicode"
set gfxmode=auto
insmod all_video
insmod gfxterm
set locale_dir=$prefix/locale
set lang=en_US
insmod gettext

terminal_output gfxterm
insmod gfxmenu
insmod png

set timeout_style=menu
set timeout=8
set default=0
### END /etc/grub.d/00_header ###

EOF


# Call this method for every kernel to add it to the newly generated boot menu
# Usage: addKernelToBootMenu <absolutePathToGuestKernel>
function addKernelToBootMenu() {
	kernelDir="$1";
	kernelName=$(basename "$kernelDir");
	kernelVersion="${kernelName#linux-*}";
	kernelBinPath="${kernelDir}/arch/x86_64/boot/bzImage";
	kernelRamdiskPath="${LAPAS_GUESTROOT_DIR}/boot/ramdisk-${kernelVersion}";
	if [ ! -f "${kernelBinPath}" ]; then return 0; fi
	cp "${kernelBinPath}" "${LAPAS_GUESTROOT_DIR}/boot/bzImage-${kernelVersion}";
	echo "Adding ${kernelName} to bootmenus...";
	if [ ! -f "$kernelRamdiskPath" ] || [ "$kernelBinPath" -nt "$kernelRamdiskPath" ]; then
		echo "Kernel binary (${kernelVersion}) newer than corresponding ramdisk. Updating ramdisk...";
		pushd "${LAPAS_GUESTROOT_DIR}" || exit 1
			./bin/arch-chroot ./ mkinitcpio -k "$kernelVersion" -c /lapas/mkinitcpio.conf -g "/boot/ramdisk-${kernelVersion}" || exit $?;
		popd
	fi
	cat <<EOF >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg"
#############################################################################
menuentry 'User-${kernelVersion}' {
	echo "Loading Kernel ${kernelVersion} [USER] ..."
	linux /boot/bzImage-${kernelVersion} ${GUEST_USER_OPTIONS} init=/lib/systemd/systemd
	echo "Loading Ramdisk ${kernelVersion} ..."
	initrd /boot/ramdisk-${kernelVersion}
	echo "Starting ..."
}
menuentry 'User-${kernelVersion} NVIDIA' {
	echo "Loading Kernel ${kernelVersion} [USER NVIDIA] ..."
	linux /boot/bzImage-${kernelVersion} ${GUEST_USER_OPTIONS} init=/lib/systemd/systemd lapas_nvidia nouveau.blacklist=yes
	echo "Loading Ramdisk ${kernelVersion} ..."
	initrd /boot/ramdisk-${kernelVersion}
	echo "Starting ..."
}
menuentry 'Admin-${kernelVersion}' {
	echo "Loading Kernel ${kernelVersion} [ADMIN] ..."
	linux /boot/bzImage-${kernelVersion} ${GUEST_ADMIN_OPTIONS} init=/lib/systemd/systemd
	echo "Loading Ramdisk ${kernelVersion} ..."
	initrd /boot/ramdisk-${kernelVersion}
	echo "Starting ..."
}

EOF
}

while read -r kernelDir; do
	addKernelToBootMenu "$kernelDir";
done <<< $(find "${LAPAS_GUESTROOT_DIR}/usr/src/" -type d -name "linux-*" | sort --version-sort -r);

chmod a+r -R "${LAPAS_TFTP_DIR}/boot";
