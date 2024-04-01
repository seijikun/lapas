#!/bin/bash
if [ ! "$BASH_VERSION" ] ; then exec /bin/bash "$0" "$@"; fi
SELF_PATH=$(realpath "$0");


# CONSTANTS
##############################
LAPAS_SUBNET_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,3}$";
MAC_REGEX="(?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2})";

LAPAS_GUEST_KERNEL_VERSION="6.8.2"; # https://kernel.org
LAPAS_GUEST_BINDFS_VERSION="1.17.6"; # https://bindfs.org/downloads/
LAPAS_GUEST_NVIDIADRIVER_VERSION="550.67" # https://www.nvidia.com/Download/driverResults.aspx/223426/en-us/
##############################


function printHeader() {
	echo "
		██▓    ▄▄▄       ██▓███   ▄▄▄        ██████ 
		▓██▒   ▒████▄    ▓██░  ██▒▒████▄    ▒██    ▒ 
		▒██░   ▒██  ▀█▄  ▓██░ ██▓▒▒██  ▀█▄  ░ ▓██▄   
		▒██░   ░██▄▄▄▄██ ▒██▄█▓▒ ▒░██▄▄▄▄██   ▒   ██▒
		░██████▒▓█   ▓██▒▒██▒ ░  ░ ▓█   ▓██▒▒██████▒▒
		░ ▒░▓  ░▒▒   ▓▒█░▒▓▒░ ░  ░ ▒▒   ▓▒█░▒ ▒▓▒ ▒ ░
		░ ░ ▒  ░ ▒   ▒▒ ░░▒ ░       ▒   ▒▒ ░░ ░▒  ░ ░
		░ ░    ░   ▒   ░░         ░   ▒   ░  ░  ░  
		    ░  ░     ░  ░               ░  ░      ░
		
		Installer v0.5.2
	";
}

#!import helpers/logging.sh
#!import helpers/process.sh
#!import helpers/system.sh
#!import helpers/arrays.sh
#!import helpers/ipcalc.sh

#!import ui/cli.sh
#!import ui/dialog.sh

#!import file/binaryPayload.sh
#!import file/configure.sh
#!import file/pushpop.sh





########################################################################################################################
########################################################################################################################
########################################################################################################################

printHeader;

if [ "$USER" != "root" ]; then
	logError "This installer has to be executed as root! 'su root' or 'sudo' may not work, direrctly log in as root or use 'su - root' instead!"; exit 1;
fi

logMakeSure "WARNING: Do not run this from an SSH session, since midway the network will be reset! At least use a screen or something.";
logMakeSure "WARNING: This installer is meant to be run on a clean-install of debian.";
logMakeSure "WARNING: This \"distribution\" is not hardened, and not meant for environments where the users aren't trustable!";

################################################
logSection "Preparing environment";
logInfo "Installing dependencies...";
# mask the services we want to install because someone at Debian thought it was a good idea
# to just start them while they are installed (:facepalm:).
systemctl mask dnsmasq;
runSilentUnfallible apt-get install -y dialog ethtool gdisk dosfstools openssh-server ntp pxelinux libnfs-utils grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin binutils nfs-kernel-server dnsmasq;
systemctl unmask dnsmasq;

################################################
logSection "Configuration";
LAPAS_BASE_DIR=$(pwd);
LAPAS_SCRIPTS_DIR="${LAPAS_BASE_DIR}/scripts";
LAPAS_TFTP_DIR="${LAPAS_BASE_DIR}/tftp";
LAPAS_GUESTROOT_DIR="${LAPAS_BASE_DIR}/guest";
LAPAS_USERHOMES_DIR="${LAPAS_BASE_DIR}/homes";
LAPAS_DNS_HOSTMAPPINGS_DIR="/tmp/lapas_dns_hostmappings";
LAPAS_TIMEZONE=$(getSystemTimezone);
LAPAS_KEYMAP=$(getSystemKeymap);
LAPAS_PASSWORD_SALT="lApAsPaSsWoRdSaLt_";
LAPAS_NET_DOMAIN=$(hostname -d);

uiSelectNetworkDevices "single" "Select the upstream network card (house network / with internet connection)\nThis will be configured as dhcp client.
Hint: Use 'ethtool --identify <enp...>' in a second terminal to identify the NICs listed here." LAPAS_NIC_UPSTREAM || exit 1;
uiSelectNetworkDevices "multi" "Select the internal lapas network card(s). If you select multiple NICs, a bond will be created, combining all of them to one large virtual network card.
Hint: Use 'ethtool --identify <enp...>' in a second terminal to identify the NICs listed here." LAPAS_NIC_INTERNAL || exit 1;
uiTextInput "Input LAPAS' internal ip address and subnet (form: xxx.xxx.xxx.1/yy).\nWARNING: Old games might not handle 10.0.0.0/8 networks very well.\nWARNING:This MUST NOT collidate with your upstream network addresses." "192.168.42.1/24" "${LAPAS_SUBNET_REGEX}" LAPAS_NET_ADDRESS || exit 1;
uiTextInput "Input the password you want to use for all administration accounts." "lapas" ".+" LAPAS_PASSWORD || exit 1;
LAPAS_NET_IP=$(fqIpGetIPAddress "$LAPAS_NET_ADDRESS")
LAPAS_NET_SUBNET_BASEADDRESS=$(fqIpGetSubnetAddress "$LAPAS_NET_ADDRESS");
LAPAS_NET_NETMASK=$(fqIpGetNetmask "$LAPAS_NET_ADDRESS");
LAPAS_NET_DHCP_ADDRESSES_START=$(fqIpGetNthUsableHostaddress "$LAPAS_NET_ADDRESS" 10);
LAPAS_NET_DHCP_ADDRESSES_END=$(fqIpGetLastUsableHostaddress "$LAPAS_NET_ADDRESS");
LAPAS_NFS_VERSION="4.2";
LAPAS_NFS_USER_MOUNTOPTIONS="vers=${LAPAS_NFS_VERSION},noatime,nodiratime,nconnect=4";

CONFIGURATION_OVERVIEW="\
Host System:
	- Timezone: ${LAPAS_TIMEZONE}
	- Keymap: ${LAPAS_KEYMAP}
	- Locale:
$(cat /etc/default/locale | grep --invert-match -E "^#" | sed 's/^/\t  /')
	Upstream Network:
		- Adapter: ${LAPAS_NIC_UPSTREAM}
	Lapas Network:
		- Domain: ${LAPAS_NET_DOMAIN}
		- Adapter(s): ${LAPAS_NIC_INTERNAL[@]}
		- Subnet Base-Address: ${LAPAS_NET_SUBNET_BASEADDRESS}
		- Lapas IP: ${LAPAS_NET_IP}
		- Lapas Netmask: ${LAPAS_NET_NETMASK}
		- DHCP Address Range: ${LAPAS_NET_DHCP_ADDRESSES_START} - ${LAPAS_NET_DHCP_ADDRESSES_END}
	Filesystem:
		- Install Base: ${LAPAS_BASE_DIR}
		- Scripts: ${LAPAS_SCRIPTS_DIR}
		- TFTP Dir: ${LAPAS_TFTP_DIR}
		- GuestRoot Dir: ${LAPAS_GUESTROOT_DIR}
		- User Homefolder Dir: ${LAPAS_USERHOMES_DIR}
Guest System:
	- Kernel Version: ${LAPAS_GUEST_KERNEL_VERSION}
	- Keymap [copied from host]: ${LAPAS_KEYMAP}
	- Locale [copied from host]:
$(cat /etc/default/locale | grep --invert-match -E "^#" | sed 's/^/\t  /')

Continue?
";
echo "$CONFIGURATION_OVERVIEW";

LAPAS_CONFIGURATION_OPTIONS=(
	"LAPAS_NET_ADDRESS=${LAPAS_NET_ADDRESS}"
	"LAPAS_NET_DOMAIN=${LAPAS_NET_DOMAIN}"
	"LAPAS_NET_SUBNET_BASEADDRESS=${LAPAS_NET_SUBNET_BASEADDRESS}"
	"LAPAS_NET_IP=${LAPAS_NET_IP}"
	"LAPAS_NET_NETMASK=${LAPAS_NET_NETMASK}"
	"LAPAS_NIC_UPSTREAM=${LAPAS_NIC_UPSTREAM}"
	"LAPAS_NIC_INTERNAL=${LAPAS_NIC_INTERNAL[@]}"
	"LAPAS_NET_DHCP_ADDRESSES_START=${LAPAS_NET_DHCP_ADDRESSES_START}"
	"LAPAS_NET_DHCP_ADDRESSES_END=${LAPAS_NET_DHCP_ADDRESSES_END}"
	"LAPAS_TFTP_DIR=${LAPAS_TFTP_DIR}"
	"LAPAS_GUESTROOT_DIR=${LAPAS_GUESTROOT_DIR}"
	"LAPAS_USERHOMES_DIR=${LAPAS_USERHOMES_DIR}"
	"LAPAS_SCRIPTS_DIR=${LAPAS_SCRIPTS_DIR}"
	"LAPAS_KEYMAP=${LAPAS_KEYMAP}"
	"LAPAS_PASSWORD_SALT=${LAPAS_PASSWORD_SALT}"
	"LAPAS_PASSWORD_HASH=$(echo -n "${LAPAS_PASSWORD_SALT}${LAPAS_PASSWORD}" | sha512sum | cut -d' ' -f1)"
	"LAPAS_NFS_VERSION=${LAPAS_NFS_VERSION}"
	"LAPAS_NFS_USER_MOUNTOPTIONS=${LAPAS_NFS_USER_MOUNTOPTIONS}"
	"LAPAS_DNS_HOSTMAPPINGS_DIR=${LAPAS_DNS_HOSTMAPPINGS_DIR}"
);

cliYesNo "This is your configuration. Continue?" resultConfigCheckOk;
if [ "$resultConfigCheckOk" == "no" ]; then
	logInfo "Aborting...";
	exit 1;
fi



################################################################################################
logSection "Setting up Guest OS (Archlinux base installation)...";
################################################################################################
# see: https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#From_a_host_running_another_Linux_distribution
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}";
runSilentUnfallible mount -o bind "${LAPAS_GUESTROOT_DIR}" "${LAPAS_GUESTROOT_DIR}";
echo "${LAPAS_GUESTROOT_DIR} ${LAPAS_GUESTROOT_DIR} none bind 0 0" >> "/etc/fstab" || exit 1;
pushd "${LAPAS_GUESTROOT_DIR}";
	logSubsection "Downloading Archlinux Bootstrap...";
	wget https://ftp.fau.de/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.gz || exit 1;
	logSubsection "Preparing Archlinux Bootstrap...";
	runSilentUnfallible tar xzf archlinux-bootstrap-x86_64.tar.gz --strip-components=1 --numeric-owner;
	rm archlinux-bootstrap-x86_64.tar.gz;
popd;

logSubsection "Setting up locale and time settings"
# TODO: Ugh... debian11 does not yet have systemd-firstboot in its distro (about to change in the future, bug already fixed).
# refactor this manual stuff to systemd-firstboot --root="<guest>" --copy
cat /etc/locale.gen | grep -v -E "^#" | grep -E "[a-zA-Z]+" >> "${LAPAS_GUESTROOT_DIR}/etc/locale.gen";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" locale-gen;
#runSilentUnfallible cp "/etc/default/locale" "${LAPAS_GUESTROOT_DIR}/etc/default/locale";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemd-firstboot --force --timezone="${LAPAS_TIMEZONE}" \
	--root-password="${LAPAS_PASSWORD}" --setup-machine-id --hostname="guest";

logSubsection "Setting up software repository"
# setup guest by initializing software repository (enable multilib for wine)
echo 'Server = http://ftp.fau.de/archlinux/$repo/os/$arch' >> "${LAPAS_GUESTROOT_DIR}/etc/pacman.d/mirrorlist";
echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> "${LAPAS_GUESTROOT_DIR}/etc/pacman.conf";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman-key --init;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman-key --populate archlinux;

logSubsection "Installing dependencies for minimal LAPAS Guest system"
# installing dependencies
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman -Syu --noconfirm;
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman --noconfirm -S nano base-devel bc wget \
	mkinitcpio mkinitcpio-nfs-utils linux-firmware nfs-utils \
	xfce4 xfce4-goodies gvfs xorg-server lightdm lightdm-gtk-greeter pulseaudio pulseaudio-alsa pavucontrol alsa-oss \
	firefox geany file-roller openbsd-netcat \
	wine-staging winetricks zenity autorandr \
	lib32-libxcomposite lib32-libpulse || exit 1;



################################################################################################
logSection "Setting up Guest OS Network Settings..."
################################################################################################
# use systemd-resolvd (enables us to use resolvectl)
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable systemd-resolved
echo "NTP=${LAPAS_NET_IP}" >> "${LAPAS_GUESTROOT_DIR}/etc/systemd/timesyncd.conf";


################################################################################################
logSection "Extracting LAPAS resources..."
################################################################################################
streamBinaryPayload "${SELF_PATH}" "__PAYLOAD_LAPAS_RESOURCES__" | base64 -d | gzip -d | tar -x --no-same-owner || exit 1;
runSilentUnfallible configureOptionsToFile "${LAPAS_SCRIPTS_DIR}/config" "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace "${LAPAS_GUESTROOT_DIR}/etc/resolv.conf" "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace "${LAPAS_GUESTROOT_DIR}/etc/initcpio/hooks/lapas" "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace "${LAPAS_GUESTROOT_DIR}/etc/systemd/system/lapas-firstboot-setup.service" "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible chown -R 1000:1000 "${LAPAS_GUESTROOT_DIR}/mnt/homeBase";
runSilentUnfallible chmod a+r "${LAPAS_GUESTROOT_DIR}/lapas/setupShell.sh";

pushd "/";
	streamBinaryPayload "${SELF_PATH}" "__PAYLOAD_SERVER_RESOURCES__" | base64 -d | gzip -d | tar -x --no-same-owner || exit 1;
popd;
runSilentUnfallible configureFileInplace /etc/systemd/system/lapas-api-server.service "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace /etc/dnsmasq.conf "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace /etc/exports "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace /etc/systemd/network/20-upstream.network "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace /etc/systemd/network/30-lapas.netdev "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace /etc/systemd/network/32-lapas.network "${LAPAS_CONFIGURATION_OPTIONS[@]}";



################################################################################################
logSection "Setting up Guest OS Kernel..."
################################################################################################
logSubsection "Downloading Guest OS Kernel..."
pushd "${LAPAS_GUESTROOT_DIR}/usr/src" || exit 1;
	wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LAPAS_GUEST_KERNEL_VERSION}.tar.xz || exit 1;
	runSilentUnfallible tar xvf ./linux-${LAPAS_GUEST_KERNEL_VERSION}.tar.xz;
	runSilentUnfallible rm ./linux-${LAPAS_GUEST_KERNEL_VERSION}.tar.xz;
	KERNEL_DIR="/usr/src/linux-${LAPAS_GUEST_KERNEL_VERSION}";
	streamBinaryPayload "$SELF_PATH" "__PAYLOAD_GUEST_KERNEL_CONF__" | base64 -d | gzip -d > "${LAPAS_GUESTROOT_DIR}/${KERNEL_DIR}/.config" || exit 1;
popd || exit 1;

logSubsection "Configuring Guest Kernel..."
# Use default parameters for new config options
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd ${KERNEL_DIR} && make olddefconfig" || exit 1;
while true; do
	uiYesNo "Kernel Config" "[Expert Only: If unsure, press No]\nI configured your guest kernel with my config. Do you want to make any further changes to the config before I start compiling?" resultSpawnMenuconfig;
	if [ "$resultSpawnMenuconfig" == "no" ]; then
		break;
	fi
	"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd ${KERNEL_DIR} && make menuconfig" || exit 1;
done

logSection "Compiling and Installing your kernel...";
while true; do
	"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd ${KERNEL_DIR} && make -j$(nproc) | tee /tmp/kernel_build.log";
	BUILD_EXIT_CODE=$?;
	if [ "${BUILD_EXIT_CODE}" == "0" ]; then break; fi
	LAST_LOG_MSGS=$(tail -n30 /tmp/kernel_build.log);
	uiYesNo "Kernel Build failed (exit code: ${BUILD_EXIT_CODE})" "Kernel build failed. This happens sometimes and a simple retry can make it work. Do you want to try again?\n\nLast log excerpt:\n${LAST_LOG_MSGS}" resultTryBuildAgain;
	if [ "$resultTryBuildAgain" == "no" ]; then
		exit 1;
	fi
done
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd ${KERNEL_DIR} && make modules_install" || exit 1;

logSubsection "Compiling and Installing bindfs...";
#bindfs is not in arch repo, so we need to build from source
mkdir -p "${LAPAS_GUESTROOT_DIR}/lapas/bindfs";
pushd "${LAPAS_GUESTROOT_DIR}/lapas/bindfs" || exit 1;
	wget https://bindfs.org/downloads/bindfs-${LAPAS_GUEST_BINDFS_VERSION}.tar.gz || exit 1;
	runSilentUnfallible tar -xpf ./bindfs-${LAPAS_GUEST_BINDFS_VERSION}.tar.gz;
	"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /lapas/bindfs/bindfs-${LAPAS_GUEST_BINDFS_VERSION} && ./configure && make && make install" || exit 1;
popd || exit 1;


################################################################################################
logSection "Setting up Guest OS Boot Process..."
################################################################################################
runSilentUnfallible grub-mknetdir --net-directory="${LAPAS_TFTP_DIR}" --subdir=grub2;
echo "${LAPAS_GUESTROOT_DIR}/boot ${LAPAS_TFTP_DIR}/boot none bind 0 0" >> "/etc/fstab" || exit 1;
runSilentUnfallible mount -o bind "${LAPAS_GUESTROOT_DIR}/boot" "${LAPAS_TFTP_DIR}/boot";

cat <<EOF >> "${LAPAS_GUESTROOT_DIR}/etc/fstab"
${LAPAS_NET_IP}:/homes      /mnt/homes      nfs     ${LAPAS_NFS_USER_MOUNTOPTIONS} 0 0
EOF
# Set keymap with init service instead, because it then also creates the x11 keymap
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-firstboot-setup;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-filesystem;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-api-daemon;

# We support the proprietary nvidia kernel through a secondary boot option that masks novueau and
# installs the proprietary nvidia driver upon boot (into overlayfs tmpfs / ram of a guest).
# This takes a while to boot but is the only sensible option because this driver just creates such a fucking mess
# Unfortunately, nouveau is completely useless for new hardware, so we need this
logSubsection "Setting up support for proprietary Nvidia driver"
pushd "${LAPAS_GUESTROOT_DIR}/lapas/drivers/nvidia" || exit 1;
	wget "https://us.download.nvidia.com/XFree86/Linux-x86_64/${LAPAS_GUEST_NVIDIADRIVER_VERSION}/NVIDIA-Linux-x86_64-${LAPAS_GUEST_NVIDIADRIVER_VERSION}.run";
popd || exit 1;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-driver-nvidia;

logSubsection "Setting up UI, User & Home System"
# configuring pam service to manage user homefolders for players
PAM_SYSTEM_LOGIN_LAPAS_LINES="session [success=1 default=ignore]  pam_succeed_if.so  service = systemd-user quiet
session    required   pam_exec.so	stdout /lapas/mountHome.sh";
PATCHED_PAM_SYSTEM_LOGIN_CONTENTS=$(awk -v lapasLines="$PAM_SYSTEM_LOGIN_LAPAS_LINES" '/^session.*system-auth$/ { print lapasLines; print; next }1' "${LAPAS_GUESTROOT_DIR}/etc/pam.d/system-login") || exit 1;
echo -n "$PATCHED_PAM_SYSTEM_LOGIN_CONTENTS" > "${LAPAS_GUESTROOT_DIR}/etc/pam.d/system-login" || exit 1;

##############################################
# configure autostart of login manager
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lightdm;
# setup base user
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" groupadd --gid 1000 lanparty;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" useradd --gid lanparty --home-dir /mnt/homeBase --create-home --uid 1000 lapas;
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "yes \"${LAPAS_PASSWORD}\" | passwd lapas" || exit 1;
# setup lapas user management
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" install -m 0644 /libnss_lapas.so.2 /lib;
rm "${LAPAS_GUESTROOT_DIR}/libnss_lapas.so.2";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" /sbin/ldconfig -n /lib /usr/lib;

# setup boot menu and install kernel/ramdisk
runSilentUnfallible "${LAPAS_SCRIPTS_DIR}/updateBootmenus.sh";







################################################################################################
logSection "Setting up LAPAS network...";
################################################################################################
logSubsection "Configuring upstream network nics";
for netDev in "${LAPAS_NIC_INTERNAL[@]}"; do
	echo -e "[Match]\nName=${netDev}\n\n[Network]\nBond=lapas" > /etc/systemd/network/31-lapas-${netDev}.network;
done
runSilentUnfallible apt-get -y install systemd-resolved;
runSilentUnfallible systemctl disable networking # disable Debian networking
runSilentUnfallible systemctl enable systemd-networkd
runSilentUnfallible systemctl enable systemd-resolved

logSubsection "Setting up DHCP, DNS and TFTP Servers...";
################################################################################
runSilentUnfallible systemctl enable dnsmasq;
mkdir -p "${LAPAS_DNS_HOSTMAPPINGS_DIR}";


logSubsection "Setting up NFS...";
################################################################################
runSilentUnfallible mkdir -p "/srv/nfs";
runSilentUnfallible mkdir -p "/srv/nfs/guest";
runSilentUnfallible mkdir -p "/srv/nfs/homes";
echo "${LAPAS_GUESTROOT_DIR} /srv/nfs/guest none bind 0 0" >> "/etc/fstab" || exit 1;
echo "${LAPAS_USERHOMES_DIR} /srv/nfs/homes none bind 0 0" >> "/etc/fstab" || exit 1;
runSilentUnfallible systemctl daemon-reload;
runSilentUnfallible mount -o bind "${LAPAS_GUESTROOT_DIR}" "/srv/nfs/guest";
runSilentUnfallible mount -o bind "${LAPAS_USERHOMES_DIR}" "/srv/nfs/homes";
runSilentUnfallible exportfs -ra;
runSilentUnfallible systemctl restart nfs-kernel-server;


logSubsection "Setting up NTP...";
################################################################################
runSilentUnfallible systemctl enable ntpsec;


logSubsection "Setting up LAPAS API Server...";
################################################################################
runSilentUnfallible systemctl daemon-reload;
runSilentUnfallible systemctl enable lapas-api-server;




################################################################################################
logSection "Starting LAPAS Services...";
################################################################################################
runSilentUnfallible systemctl stop networking
sleep 2;
runSilentUnfallible systemctl restart systemd-networkd;
runSilentUnfallible systemctl restart systemd-resolved;
uiAwaitLinkStateUp "${LAPAS_NIC_UPSTREAM}" "${LAPAS_NIC_INTERNAL[@]}" "lapas" || exit 1;

runSilentUnfallible systemctl restart ntp;
runSilentUnfallible systemctl restart dnsmasq;
runSilentUnfallible systemctl start lapas-api-server;



LAPAS_WELCOME="
The setup of your \ZbLanPArtyServer\ZB is complete. All services are up and running, no reboot is required.


\Zb===== The Guest =====\ZB
The 'guest' is an ArchLinux installation hosted on LAPAS, that clients boot into over the network.
This guest has a base-user [name: lapas, home: /mnt/homeBase] that is not meant for actual game usage.
It's homefolder is the basis of all players' homefolders, meaning that the files within its homefolder will 'magically appear' in all players' homefolders.
Thus, you can e.g. create wine prefixes there, and they will automatically be accessible to all players without the need to copy them to every homefolder.
The player's config files and play states are layered on top of homeBase and stored individually in each player's specific permanent storage.

If a player changes any of the files that are provided by the underlying homeBase, the modified version will be stored into the players' permanent storage.
From then on, changes you make to these files as user lapas in homeBase will not reach the player's homefolder anymore. (For more information, see Linux overlayfs)
To keep this clean, LAPAS employs a '.keep' file within homeBase that contains a set of patterns and rules specifying which files are supplied \
by homeBase, and which files a user is allowed to overwrite. (see the mentioned .keep file for more information on this)

For everything other than wine (which is quite picky about file ownership and its own location), it's best to have a systemwide folder (like /games) outside homeBase, to store \
the native games that can't be installed through the repository.


\Zb===== Next Step =====\ZB
Now you can boot into your guest system, by connecting a client to LAPAS' internal network and starting its network boot functionality.
The boot menu will then present you with two options:

\ZuUser\ZU
The User mode mounts your guest immutable. This is the mode meant for actual gameplay.
Any changes made to the guest system, as well homeBase will not be permanent. (Persisted in your machines RAM -> gone after a reboot)
Changes made towards player's home directories will be persisted in the players' permanent storage.
When booting into this mode, the patterns specified in 'homeBase/.keep' are applied (once during boot); meaning that if you log into user lapas in this mode, you will only see the files \
that would be supplied to players' homefolders by homeBase.
Like this, logging into user lapas after a fresh guest system boot in user mode basically shows you what a new player account will see.


\ZuAdmin\ZU
The Admin mode mounts your guest as mutable. You should only boot into this when you plan to make permanent changes to the guest system \
(e.g. by installing new games, creating new wine bottles, etc.).
In this mode, logging into player accounts is prohibited.



\Zb===== Managing Users =====\ZB
A new user has to be added before the corresponding client (that wants to use the user) boots into the guest system.
This can either be done on the server:
> cd \"${LAPAS_BASE_DIR}\"
> ./scripts/addUser.sh <newUser>
Or by quickly logging into the lapas user using your client (in User Mode), then using the Desktop shortcut.
Directly afterwards, you can then logout and switch to your user to start gaming.
In both cases, you will be asked for a password for the new account. Letting the use change their password themselfes is not possible atm. (due to the immutable filesystem), \
so you will probably want to either use a default password or let them enter it themselfes on your machine.


===== ATTENTION =====
- If you have selected multiple internal network interfaces, you have to connect ALL of them to the same switch, then connect your clients to said switch. Do NOT connect one client per port of the bond, it won't work!
- It's best not to boot into the Admin mode while other clients are running in User mode.
- It's best not to boot multiple devices into Admin mode at the same time.


\Zb===== Important =====\ZB
Have a lot of fun! Cheers~
";
uiMsgbox "Installation complete" "${LAPAS_WELCOME}";

#TODO:
# https://github.com/util-linux/util-linux/pull/1661
# When this is supported with mount, we don't need the ugly "every user has the same uid" hack anymore.
# apparently, this also supports overlayfs, so we got this going for us - which is nice!

exit 0;



__PAYLOAD_LAPAS_RESOURCES__
#!binaryPayloadFrom cd ../res/lapas && tar -cf - ./ | gzip -9 | base64 -w 0
__PAYLOAD_LAPAS_RESOURCES__
__PAYLOAD_SERVER_RESOURCES__
#!binaryPayloadFrom cd ../res/server && tar -cf - ./ | gzip -9 | base64 -w 0
__PAYLOAD_SERVER_RESOURCES__
__PAYLOAD_GUEST_KERNEL_CONF__
#!binaryPayloadFrom cat ../res/kernel/.config | gzip -9 | base64 -w 0
__PAYLOAD_GUEST_KERNEL_CONF__
