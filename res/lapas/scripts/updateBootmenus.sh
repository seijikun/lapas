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
ISCSI_NETROOT="netroot=iscsi:${LAPAS_NET_IP}::::${LAPAS_GUESTIMG_IQN}";
GUEST_USER_OPTIONS="ip=dhcp root=UUID=${LAPAS_GUESTIMG_FSUUID} ro ${ISCSI_NETROOT} rd.retry=45 rd.timeout=45 rd.live.overlay.overlayfs=1";
GUEST_ADMIN_OPTIONS="ip=dhcp root=UUID=${LAPAS_GUESTIMG_FSUUID} rw ${ISCSI_NETROOT} rd.retry=45 rd.timeout=45";

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
if [ -d "${LAPAS_TFTP_DIR}/grub2/themes" ]; then
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
fi

echo -e "\n### END /etc/grub.d/00_header ###\n\n" >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg";

################################################################################################

# Call this method for every kernel to add it to the newly generated boot menu
# Usage: addKernelToBootMenu <absolutePathToGuestKernel>
function addKernelToBootMenu() {
	kernelVersion="$1";
	kernelBinPath="${LAPAS_TFTP_DIR}/boot/vmlinuz-${kernelVersion}";
	kernelRamdiskPath="${LAPAS_TFTP_DIR}/boot/initrd-${kernelVersion}";
	if [ ! -f "${kernelBinPath}" ]; then return 0; fi
	echo "Adding ${kernelVersion} to bootmenus...";
	cat <<EOF >> "${LAPAS_TFTP_DIR}/grub2/grub.cfg"
#############################################################################
menuentry 'User-${kernelVersion}' {
	insmod all_video
	set gfxpayload=keep

	echo "Loading Kernel ${kernelVersion} [USER] ..."
	linux /boot/vmlinuz-${kernelVersion} ${GUEST_USER_OPTIONS} init=/lib/systemd/systemd nouveau.config=NvGspRm=1
	echo "Loading Ramdisk ${kernelVersion} ..."
	initrd /boot/initrd-${kernelVersion}
	echo "Starting ..."
}
menuentry 'Admin-${kernelVersion}' {
	echo "Loading Kernel ${kernelVersion} [ADMIN] ..."
	linux /boot/vmlinuz-${kernelVersion} ${GUEST_ADMIN_OPTIONS} init=/lib/systemd/systemd
	echo "Loading Ramdisk ${kernelVersion} ..."
	initrd /boot/initrd-${kernelVersion}
	echo "Starting ..."
}

EOF
}

# copy kernel/initramfs images from guest to tftp folder
rm -rf "${LAPAS_TFTP_DIR}/boot";
cp -aLR "${LAPAS_GUESTROOT_DIR}/boot" "${LAPAS_TFTP_DIR}/boot" || { echo "ERROR: Failed to copy over boot folder from guest"; exit 1; }
# copy signed shim and grub images (to be safe, in case the signing key changes)
cp "${LAPAS_GUESTROOT_DIR}/usr/share/efi/x86_64/shim.efi" "${LAPAS_TFTP_DIR}/shim.efi";
cp "${LAPAS_GUESTROOT_DIR}/usr/share/efi/x86_64/grub.efi" "${LAPAS_TFTP_DIR}/grub.efi";
cp "${LAPAS_GUESTROOT_DIR}/usr/share/efi/x86_64/MokManager.efi" "${LAPAS_TFTP_DIR}/MokManager.efi";

while read -r kernelConfig; do
	kernelConfigFilename=$(basename "$kernelConfig");
	kernelVersion="${kernelConfigFilename#config-*}";
	echo "Found kernel: ${kernelVersion}";
	addKernelToBootMenu "${kernelVersion}";
done <<< $(find "${LAPAS_TFTP_DIR}/boot" -name "config-*" | sort --version-sort -r);

chmod a+r -R "${LAPAS_TFTP_DIR}";
