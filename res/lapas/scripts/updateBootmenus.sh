#!/bin/bash
if [ "$USER" != "root" ]; then
	echo "You have to be logged in as root to use this. Hint: use 'su - root' instead of su root"; exit 1;
fi

# Ensure the script is running in bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script must be run with bash, not sh."
    exit 1
fi


# import LAPAS config
. $(dirname "$0")/config;
# KERNEL-CMDLINE
GUEST_USER_OPTIONS="ip=dhcp carrier_timeout=10 lapas_mode=user";
GUEST_ADMIN_OPTIONS="ip=dhcp carrier_timeout=10 lapas_mode=admin";

################################################################################################
# GRUB.CFG PREAMBLE

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

EOF

# if there is a theme folder, setup theme
themePath=$(find "${LAPAS_TFTP_DIR}/grub2/themes" -maxdepth 1 -type d | sed -n '2p');
if [ -d "$themePath" ]; then
	themeName=$(basename "$themePath");
	echo "Using Theme: $themeName";

	# Load all theme fonts
	find "$themePath" -type f -name "*.pf2" -print0 | while read -d $'\0' fontFile; do
		fontFileName=$(basename "$fontFile");
		echo "loadfont \$prefix/themes/${themeName}/${fontFileName}" >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg";
	done

	echo "set theme=\$prefix/themes/${themeName}/theme.txt" >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg";
	echo "export theme" >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg";
fi

echo -e "\n### END /etc/grub.d/00_header ###\n\n" >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg";

################################################################################################

# Call this method for every kernel to add it to the newly generated boot menu
# Usage: addKernelToBootMenu <absolutePathToGuestKernel>
function addKernelToBootMenu() {
	kernelDir="$1";
	kernelName=$(basename "$kernelDir");
	kernelVersion="${kernelName#linux-*}";
	kernelBinPath="${kernelDir}/arch/x86_64/boot/bzImage";
	kernelRamdiskPath="${LAPAS_GUESTROOT_DIR}/boot/ramdisk-${kernelVersion}";
	if [ ! -f "${kernelBinPath}" ]; then return 0; fi
	cp "${kernelBinPath}" "${LAPAS_GUESTROOT_DIR}/boot/vmlinuz-${kernelVersion}";
	echo "Adding ${kernelName} to bootmenus...";
	if [ ! -f "$kernelRamdiskPath" ] || [ "$kernelBinPath" -nt "$kernelRamdiskPath" ] || [ "${LAPAS_GUESTROOT_DIR}/lapas/mkinitcpio.conf" -nt "$kernelRamdiskPath" ]; then
		echo "Something changed, ramdisk recreation necessary. Updating ramdisk...";
		pushd "${LAPAS_GUESTROOT_DIR}" || exit 1
			./bin/arch-chroot ./ mkinitcpio -k "$kernelVersion" -c /lapas/mkinitcpio.conf -g "/boot/ramdisk-${kernelVersion}" || exit $?;
		popd
	fi
	cat <<EOF >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg"
#############################################################################
menuentry 'User-${kernelVersion}' {
	insmod all_video
	set gfxpayload=keep

	echo "Loading Kernel ${kernelVersion} [USER] ..."
	linux /boot/vmlinuz-${kernelVersion} ${GUEST_USER_OPTIONS} init=/lib/systemd/systemd nouveau.config=NvGspRm=1
	echo "Loading Ramdisk ${kernelVersion} ..."
	initrd /boot/ramdisk-${kernelVersion}
	echo "Starting ..."
}
menuentry 'Admin-${kernelVersion}' {
	echo "Loading Kernel ${kernelVersion} [ADMIN] ..."
	linux /boot/vmlinuz-${kernelVersion} ${GUEST_ADMIN_OPTIONS} init=/lib/systemd/systemd
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
