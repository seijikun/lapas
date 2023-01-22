#!/bin/bash

# CONSTANTS
##############################
LAPAS_SUBNET_REGEX="([0-9]{1,3}\.){3}1/[0-9]{1,2}";
MAC_REGEX="(?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2})";

LAPAS_REPOFILE_URL="https://raw.githubusercontent.com/seijikun/lapas/main/files";
LAPAS_GUEST_KERNEL_VERSION="6.1.6";
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
		
		Installer v0.1
	";
}

# GENERAL PURPOSE FUNCTIONS
##############################
function logMakeSure() {
	echo -e "\e[1;33m$@\e[0m";
	echo "Press enter to continue..."
	read
}
function logSection() {	echo -e "\e[1;32m$@\n########################\e[0m"; }
function logSubsection() { echo -e "\e[1m# $@\e[0m"; }
function logError() { echo -e "\e[31m$@\e[0m"; }
function logInfo() {
	if [ "$#" == "0" ]; then # log from stdin
		cat;
	else # log from parameters
		echo -e "$@";
	fi
}
function logEmptyLine { echo -n ""; }

function runSilentUnfallible() {
	logInfo "Running: $@";
	cmdOutput=$($@ 2>&1 >/dev/null);
	resultCode="$?";
	if [ "$resultCode" != "0" ]; then
		logError "Command: > $@ < exited unexpectedly with error code: $resultCode";
		logError "Command-Output:";
		logError "#####################"
		logError "${cmdOutput}";
		logError "#####################"
		logError "Aborting...";
		exit 1;
	fi
}


# ENVIRONMENT FUNCTIONS
##############################
function getUserList() { awk -F':' '{ print $1 }' /etc/passwd; }
function getGroupList() { awk -F':' '{ print $1 }' /etc/group; }
function assertUserExists() {
	if [ $(getUserList | grep "^$1"| wc -l) == "0" ]; then
		logError "$2"; exit 1;
	fi
}
function assertGroupExists() {
	if [ $(getGroupList | grep "^$1"| wc -l) == "0" ]; then
		logError "$2"; exit 1;
	fi
}

function getSystemTimezone() {
	TIMEZONE_PATH=$(readlink "/etc/localtime");
	echo "${TIMEZONE_PATH#/usr/share/zoneinfo/*}";
}
function getSystemKeymap() {
	result=$(cat /etc/default/keyboard | grep -E "^XKBLAYOUT=");
	result="${result#*=\"}";
	echo "${result%\"}";
}


# converts an int to a netmask as 24 -> 255.255.255.0
# see: http://filipenf.github.io/2015/12/06/bash-calculating-ip-addresses/
function netmaskFromBits() {
    local mask=$((0xffffffff << (32 - $1))); shift
    local ip n
    for n in 1 2 3 4; do
        ip=$((mask & 0xff))${ip:+.}$ip
        mask=$((mask >> 8))
    done
    echo $ip
}




# CLI FUNCTIONS
##############################

# CLI asking yes/no question and validating result
# cliYesNo <prompt> <resultVarName>
function cliYesNo() {
	while true; do
		echo -n "$1 [yes/no]: ";
		read result;
		if [[ "$result" == "yes" || "$result" == "no" ]]; then
			declare -g $2="$result";
			break;
		fi
	done
}


# UI FUNCTIONS
##############################
function uiDialogWithResult {
	resultVariableName="$1";
	shift;
	resultFile=$(mktemp);
	dialog "$@" 2>${resultFile};
	result=$?;
	resultData=$(cat "$resultFile"); rm "$resultFile";
	declare -g $resultVariableName="$resultData";
	return $result;
}

function uiMsgbox() {
	dialog --erase-on-exit --colors --title "$1" --msgbox "$2" 0 0;
}

# Show dialog with prompt that asks yes/no question
# uiYesNo <prompt> <resultVarName>
function uiYesNo() {
	dialog --erase-on-exit --yesno "$1" 0 0;
	if [ "$?" == "0" ]; then
		declare -g $2="yes";
	else
		declare -g $2="no";
	fi
}

# Show dialog to select network device(s)
# uiSelectNetworkDevices <multi|single> <message> <resultVarName>
function uiSelectNetworkDevices() {
	listType="radiolist";
	if [ "$1" == "multi" ]; then
		listType="checklist";
	fi
	networkDeviceDialogOptions=$(ip -brief link show | grep --invert-match "LOOPBACK" | awk '{ print $1,$3,"off" }');
	networkDeviceCnt=$(echo "$networkDeviceDialogOptions" | wc -l);
	while true; do
		uiDialogWithResult "tmpResult" --erase-on-exit --$listType "$2" 0 0 $networkDeviceCnt $networkDeviceDialogOptions;
		if [ "$?" != "0" ]; then exit 1; fi
		if [ "$tmpResult" == "" ]; then
			uiMsgbox "Input Error" "You have to select something";
		else
			break;
		fi
	done
	read -r -a "$3" <<< $tmpResult; #re-declare output to array
	return $?;
}

# Show dialog that lets user input text
# uiTextInput <prompt> <defaultValue> <validationRegex> <resultVarName>
function uiTextInput() {
	while true; do
		uiDialogWithResult "$4" --erase-on-exit --inputbox "$1" 0 0 "$2";
		if [ "$?" != "0" ]; then exit 1; fi
		# check validity
		(echo "${!4}" | grep -Eq "^${3}$");
		if [ "$?" == "0" ]; then
			return 0;
		else
			uiMsgbox "Input Error" "The input value was invalid. Try again.";
		fi
	done
}








########################################################################################################################
########################################################################################################################
########################################################################################################################

if [ $(whoami) == "seiji" ]; then

exit 0;
fi


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
runSilentUnfallible apt-get install -y dialog openssh-server tftpd-hpa pxelinux samba libnfs-utils isc-dhcp-server grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin binutils nfs-kernel-server dnsmasq;

################################################
logSection "Configuration";
LAPAS_BASE_DIR=$(pwd);
LAPAS_SCRIPTS_DIR="${LAPAS_BASE_DIR}/scripts";
LAPAS_TFTP_DIR="${LAPAS_BASE_DIR}/tftp";
LAPAS_GUESTROOT_DIR="${LAPAS_BASE_DIR}/guest";
LAPAS_USERHOMES_DIR="${LAPAS_BASE_DIR}/homes";
LAPAS_TIMEZONE=$(getSystemTimezone);
LAPAS_KEYMAP=$(getSystemKeymap);

uiSelectNetworkDevices "single" "Select the upstream network card (house network / with internet connection)\nThis will be configured as dhcp client. You can change this later on if required" LAPAS_NIC_UPSTREAM || exit 1
uiSelectNetworkDevices "multi" "Select the internal lapas network card(s). If you select multiple, a bond will be created" LAPAS_NIC_INTERNAL || exit 1
uiTextInput "Input Lapa's internal subnet (form: xxx.xxx.xxx.1/yy).\nWARNING: Old games might not handle 10.0.0.0/8 networks very well.\nWARNING:This MUST NOT collidate with your upstream network addresses." "192.168.42.1/24" "${LAPAS_SUBNET_REGEX}" LAPAS_NET_ADDRESS || exit 1
LAPAS_NET_IP=${LAPAS_NET_ADDRESS%/*};
LAPAS_NET_SUBNET_BASEADDRESS="${LAPAS_NET_ADDRESS%.1/*}.0";
LAPAS_NET_NETMASK=$(netmaskFromBits ${LAPAS_NET_ADDRESS#*/});

logSection "Configuration Overview"
logInfo "Host System:";
logInfo "\t- Timezone: ${LAPAS_TIMEZONE}";
logInfo "\t- Keymap: ${LAPAS_KEYMAP}";
logInfo "\t- Locale [copied from host]:";
cat /etc/default/locale | grep --invert-match -E "^#" | sed 's/^/\t\t/' | logInfo;
logInfo "Guest System:";
logInfo "\t- Kernel Version: ${LAPAS_GUEST_KERNEL_VERSION}";
logInfo "Filesystem:";
logInfo "\t- Install Base: ${LAPAS_BASE_DIR}";
logInfo "\t- Scripts: ${LAPAS_SCRIPTS_DIR}";
logInfo "\t- TFTP Dir: ${LAPAS_TFTP_DIR}";
logInfo "\t- GuestRoot Dir: ${LAPAS_GUESTROOT_DIR}";
logInfo "\t- User Homefolder Dir: ${LAPAS_USERHOMES_DIR}";
logInfo "Upstream Network:";
logInfo "\t- Adapter: ${LAPAS_NIC_UPSTREAM}";
logInfo "Lapas Network:";
logInfo "\t- Adapter(s): ${LAPAS_NIC_INTERNAL[@]}";
logInfo "\t- Subnet Base-Address: ${LAPAS_NET_SUBNET_BASEADDRESS}"
logInfo "\t- Lapas IP: ${LAPAS_NET_IP}";
logInfo "\t- Lapas Netmask: ${LAPAS_NET_NETMASK}"
logEmptyLine;

cliYesNo "This is your configuration. Continue?" resultConfigCheckOk;
if [ "$resultConfigCheckOk" == "no" ]; then
	logInfo "Aborting...";
	exit 1;
fi


################################################
logSection "Setting up folder structure...";
runSilentUnfallible mkdir -p "${LAPAS_TFTP_DIR}";
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}";
runSilentUnfallible mkdir -p "${LAPAS_USERHOMES_DIR}";
runSilentUnfallible mkdir -p "${LAPAS_SCRIPTS_DIR}";

################################################################################
cat <<EOF > "${LAPAS_SCRIPTS_DIR}/config"
LAPAS_TFTP_DIR=${LAPAS_TFTP_DIR};
LAPAS_GUESTROOT_DIR=${LAPAS_GUESTROOT_DIR};
LAPAS_USERHOMES_DIR=${LAPAS_USERHOMES_DIR};
LAPAS_SCRIPTS_DIR=${LAPAS_SCRIPTS_DIR};
EOF
################################################################################



logSection "Setting up network...";
rm -rf /etc/systemd/network/*;
logSubsection "Configuring upstream network";
echo -e "\
[Match]
Name=${LAPAS_NIC_UPSTREAM}

[Network]
DHCP=ipv4
IPForward=true" > /etc/systemd/network/20-upstream.network;

logSubsection "Configuring Lapas network"
echo -e "\
[NetDev]
Name=lapas
Kind=bond

[Bond]
Mode=balance-rr" > /etc/systemd/network/30-lapas.netdev;
for netDev in "${LAPAS_NIC_INTERNAL[@]}"; do
	echo -e "[Match]\nName=${netDev}\n\n[Network]\nBond=lapas" > /etc/systemd/network/31-lapas-${netDev}.network;
done
echo -e "\
[Match]
Name=lapas

[Network]
BindCarrier=${LAPAS_NIC_INTERNAL[@]}
IPForward=true
#TODO: IPMasquerade=true seems to have been deprecated in favor of 'both' but that is not yet supported on debian11
IPMasquerade=true

[Address]
Address=${LAPAS_NET_ADDRESS}" > /etc/systemd/network/32-lapas.network;

runSilentUnfallible systemctl stop networking
runSilentUnfallible systemctl restart systemd-networkd
runSilentUnfallible systemctl disable networking # disable Debian networking
runSilentUnfallible systemctl enable systemd-networkd


logSubsection "Configuring DHCP Server"
################################################################################
cat <<EOF > /etc/dhcp/dhcpd.conf
allow booting;
allow bootp;

option architecture-type code 93 = unsigned integer 16;
option domain-name-servers ${LAPAS_NET_IP};
option routers ${LAPAS_NET_IP};

ddns-update-style none;
default-lease-time 86400;

group {
	if option architecture-type = 00:06 or option architecture-type = 00:07 {
		filename "grub2/x86_64-efi/core.efi";
	} else {
		filename "grub2/i386-pc/core.0";
#		filename "bios/pxelinux.0";
	}

	next-server ${LAPAS_NET_IP};
	subnet ${LAPAS_NET_SUBNET_BASEADDRESS} netmask ${LAPAS_NET_NETMASK} {
		range dynamic-bootp ${LAPAS_NET_ADDRESS%.1/*}.10 ${LAPAS_NET_ADDRESS%.1/*}.254;
		default-lease-time 86400;
		max-lease-time 172800;
	}
}
EOF
################################################################################
echo 'INTERFACESv4="lapas"' >> /etc/default/isc-dhcp-server;
runSilentUnfallible systemctl enable isc-dhcp-server
sleep 2
runSilentUnfallible systemctl restart isc-dhcp-server


logSubsection "Setting up TFTP Server...";
runSilentUnfallible grub-mknetdir --net-directory="${LAPAS_TFTP_DIR}" --subdir=grub2;
################################################################################
cat <<EOF > "${LAPAS_TFTP_DIR}/grub2/grub.cfg"
set default="0"
set timeout=5

menuentry 'User' {
	linux /bzImage ip=dhcp init=/lib/systemd/systemd
	initrd /ramdisk.img
}

menuentry 'Admin' {
	linux /bzImage ip=dhcp root=/dev/nfs rw nfsroot=${LAPAS_NET_IP}:${LAPAS_GUESTROOT_DIR},vers=3 init=/lib/systemd/systemd
}
EOF
################################################################################
cat <<EOF > "/etc/default/tftpd-hpa"
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="${LAPAS_TFTP_DIR}"
TFTP_ADDRESS="${LAPAS_NET_IP}:69"
TFTP_OPTIONS="--secure"
EOF
################################################################################
runSilentUnfallible systemctl restart tftpd-hpa;


logSubsection "Setting up DNS...";
################################################################################
cat <<"EOF" >> "/etc/dnsmasq.conf"
# enable DNS on our internal lapas bond network
interface=lapas
# disable DHCP / TFTP (dnsmasq is a little too weak for our dhcp needs)
no-dhcp-interface=
EOF
################################################################################

runSilentUnfallible systemctl enable dnsmasq;
runSilentUnfallible systemctl restart dnsmasq;


logSubsection "Setting up NFS...";
echo "\
${LAPAS_GUESTROOT_DIR} *(rw,no_root_squash,async,no_subtree_check)
${LAPAS_USERHOMES_DIR} *(rw,no_root_squash,async,no_subtree_check)
" > /etc/exports;
runSilentUnfallible exportfs -ra;
runSilentUnfallible systemctl enable rpc-statd;
runSilentUnfallible systemctl restart rpc-statd;

################################################
# see: https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#From_a_host_running_another_Linux_distribution
logSection "Setting up Guest OS (Archlinux)...";
pushd "${LAPAS_GUESTROOT_DIR}";
	logSubsection "Downloading Archlinux Bootstrap..."
	wget https://ftp.fau.de/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.gz || exit 1;
	logSubsection "Preparing Archlinux Bootstrap..."
	runSilentUnfallible tar xzf archlinux-bootstrap-x86_64.tar.gz --strip-components=1 --numeric-owner
	rm archlinux-bootstrap-x86_64.tar.gz;
popd;
runSilentUnfallible mount -o bind "${LAPAS_GUESTROOT_DIR}" "${LAPAS_GUESTROOT_DIR}";

# setup guest by initializing software repository (enable multilib for wine)
echo 'Server = http://ftp.fau.de/archlinux/$repo/os/$arch' >> "${LAPAS_GUESTROOT_DIR}/etc/pacman.d/mirrorlist";
echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> "${LAPAS_GUESTROOT_DIR}/etc/pacman.conf";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman-key --init;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman-key --populate archlinux;

# installing dependencies
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman -Syu --noconfirm;
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman --noconfirm -S nano base-devel bc wget \
	mkinitcpio mkinitcpio-nfs-utils linux-firmware nfs-utils \
	xfce4 xfce4-goodies gvfs xorg-server lightdm lightdm-gtk-greeter firefox geany \
	wine-staging winetricks zenity || exit 1;

# configure locale and time settings
# TODO: Ugh... debian11 does not yet have systemd-firstboot in its distro (about to change in the future, bug already fixed).
# refactor this manual stuff to systemd-firstboot --root="<guest>" --copy
cat /etc/default/locale | sed -r 's/^\w+="(.*)"/\1/g' | sed -n '/^.*_.*\..*/p' | uniq >> "${LAPAS_GUESTROOT_DIR}/etc/locale.gen";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" locale-gen;
#runSilentUnfallible cp "/etc/default/locale" "${LAPAS_GUESTROOT_DIR}/etc/default/locale";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemd-firstboot --force --timezone="${LAPAS_TIMEZONE}" \
	--root-password="lapas" --setup-machine-id --hostname="guest";
################################################################################
# Set keymap with init service instead, because it then also creates the x11 keymap
cat <<EOF > "${LAPAS_GUESTROOT_DIR}/etc/systemd/system/lapas-init-keymap.service"
[Unit]
ConditionPathExists=!/lapas/initflags/keymap

[Service]
Type=oneshot
ExecStart=localectl set-keymap ${LAPAS_KEYMAP}
ExecStartPost=/usr/bin/touch /lapas/initflags/keymap
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-init-keymap;
################################################################################
	
#Prepare global folder for lapas-stuff
runSilentUnfallible mkdir "${LAPAS_GUESTROOT_DIR}/lapas";
runSilentUnfallible mkdir "${LAPAS_GUESTROOT_DIR}/lapas/initflags";


logSubsection "Downloading Guest Kernel..."
pushd "${LAPAS_GUESTROOT_DIR}/usr/src";
	wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LAPAS_GUEST_KERNEL_VERSION}.tar.xz || exit 1;
	runSilentUnfallible tar xvf ./linux-${LAPAS_GUEST_KERNEL_VERSION}.tar.xz;
	runSilentUnfallible rm ./linux-${LAPAS_GUEST_KERNEL_VERSION}.tar.xz;
	runSilentUnfallible ln -sf linux-${LAPAS_GUEST_KERNEL_VERSION} ./linux;
	runSilentUnfallible wget "${LAPAS_REPOFILE_URL}/.config" --output-document="${LAPAS_GUESTROOT_DIR}/usr/src/linux/.config";
popd

logSubsection "Preparing Guest Kernel..."
# Use default parameters for new config options
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /usr/src/linux && make olddefconfig" || exit 1;
while true; do
	uiYesNo "[Expert Only]\nI configured your guest kernel with my config. Do you want to make any further changes to the config before I start compiling?" resultSpawnMenuconfig;
	if [ "$resultSpawnMenuconfig" == "no" ]; then
		break;
	fi
	"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /usr/src/linux && make menuconfig" || exit 1;
done

logSection "Compiling and Installing your kernel...";
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "cd /usr/src/linux && make -j$(nproc) && make modules_install" || exit 1;
runSilentUnfallible cp "${LAPAS_GUESTROOT_DIR}/usr/src/linux/arch/x86_64/boot/bzImage" "${LAPAS_TFTP_DIR}/bzImage";


logSubsection "Preparing Guest Ramdisk..."
################################################################################
cat <<EOF > "${LAPAS_GUESTROOT_DIR}/lapas/mkinitcpio.conf"
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev autodetect remountoverlay)
EOF
################################################################################
cat <<EOF > "${LAPAS_GUESTROOT_DIR}/etc/initcpio/install/remountoverlay"
#!/bin/bash

build() {
	add_checked_modules '/drivers/net/'
	add_module nfsv3?

	add_binary "/usr/lib/initcpio/ipconfig" "/bin/ipconfig"
	add_binary "/usr/lib/initcpio/nfsmount" "/bin/nfsmount"

	add_runscript
}

help() {
        cat <<HELPEOF
This installs our remountfs script.
HELPEOF
}
EOF
################################################################################
cat <<EOF > "${LAPAS_GUESTROOT_DIR}/etc/initcpio/hooks/remountoverlay"
run_hook() {
	ipconfig "ip=\${ip}"
	rootfstype="overlay"
	mount_handler="lapas_mount_handler"
}

lapas_mount_handler() {
	mkdir /dev/nfs
	mkdir /tmproot
	mount -t tmpfs none /tmproot
	mkdir /tmproot/upper
	mkdir /tmproot/work
	touch /tmproot/upper/.lapasUser

	nfsmount ${LAPAS_NET_IP}:${LAPAS_GUESTROOT_DIR} /dev/nfs
	mount -t overlay overlay -o lowerdir=/dev/nfs,upperdir=/tmproot/upper,workdir=/tmproot/work "\$1"
}
EOF
################################################################################

# we intentionally keep this ramdisk basically empty, so we don't have to rebuild it with every new kernel
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" mkinitcpio -k "${LAPAS_GUEST_KERNEL_VERSION}" -c /lapas/mkinitcpio.conf -g /boot/ramdisk.img;
runSilentUnfallible mv "${LAPAS_GUESTROOT_DIR}/boot/ramdisk.img" "${LAPAS_TFTP_DIR}/ramdisk.img";
runSilentUnfallible chmod a+r "${LAPAS_TFTP_DIR}/ramdisk.img";


logSubsection "Setting up UI, User & Home System"
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lightdm;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" groupadd --gid 1000 lanparty;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" useradd --gid lanparty --home-dir /mnt/homeBase --create-home --uid 1000 lapas;
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "yes lapas | passwd lapas" || exit 1;
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}/mnt/homes";
################################################################################
cat <<EOF >> "${LAPAS_GUESTROOT_DIR}/etc/fstab"
${LAPAS_NET_IP}:${LAPAS_USERHOMES_DIR}      /mnt/homes      nfs     defaults,nofail 0 0
EOF
################################################################################
cat <<EOF >> "${LAPAS_GUESTROOT_DIR}/etc/pam.d/system-login"
session       required   pam_exec.so          stdout /lapas/mountHome.sh
EOF
################################################################################
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/lapas/mountHome.sh"
#!/bin/bash

# Constants
USER_IMAGE_SIZE="16G";
USER_IMAGE_BASE="/mnt/homes";
USER_WORKDIR_BASE="/mnt/homeMounts";
USER_BASE="/mnt/homeBase";
LAPAS_USER_GROUPNAME="lanparty";

function createDir() {
	mkdir -p "$1" || exit 1;
	chown $2:$LAPAS_USER_GROUPNAME "$1" || exit 1;
}

# Only run mountHome-script for lapas users
[ $(id -ng $PAM_USER) != "$LAPAS_USER_GROUPNAME" ] && exit 0;

if [[ ! -f "/.lapasUser" && "$PAM_USER" != "lapas" ]]; then
	exit 1; # Forbid normal user to login in admin mode
fi

echo "[LOGON] Login user: $PAM_USER, home: $USER_HOME";
USER_HOME=$(getent passwd $PAM_USER | cut -d: -f6);

if [ "$PAM_USER" != "lapas" ] && [ "$PAM_TYPE" == "open_session" ]; then
	echo "[LOGON] Detected normal user";
	USER_IMAGE="${USER_IMAGE_BASE}/${PAM_USER}";
	USER_IMAGE_MOUNTDIR="${USER_WORKDIR_BASE}/${PAM_USER}";

	if [ ! -f "$USER_IMAGE" ]; then
		# create image for user-specific dynamic data
		truncate -s $USER_IMAGE_SIZE "$USER_IMAGE" || exit 1;
		mkfs.ext4 -m0 "$USER_IMAGE" || exit 1;
	fi
	if [ $(mount | grep "$USER_IMAGE" | wc -l) == 0 ]; then
		# create user-specific work folder
		createDir "$USER_IMAGE_MOUNTDIR" $PAM_USER || exit 1;
		# mount user-image
		mount "$USER_IMAGE" "$USER_IMAGE_MOUNTDIR" || exit 1;
		createDir "$USER_IMAGE_MOUNTDIR/upper" $PAM_USER || exit 1;
		createDir "$USER_IMAGE_MOUNTDIR/work" $PAM_USER || exit 1;
	fi
	if [ $(mount | grep "$USER_HOME" | wc -l) == 0 ]; then
		createDir "$USER_HOME" $PAM_USER || exit 1;
		mount -t overlay overlay -o lowerdir="${USER_BASE}",upperdir="${USER_IMAGE_MOUNTDIR}/upper",workdir="${USER_IMAGE_MOUNTDIR}/work" "$USER_HOME" || exit 1;
	fi
fi
EOF
chmod a+x "${LAPAS_GUESTROOT_DIR}/lapas/mountHome.sh";
################################################################################
echo "nameserver ${LAPAS_NET_IP}" >> "${LAPAS_GUESTROOT_DIR}/etc/resolv.conf";
################################################################################
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/mnt/homeBase/.keep"
# This file contains a list of patterns for files/folders
# Specify folders >without< trailing slashes!
# Line prefix patterns:
# 'b ' = homeBase >always< provides these file
#                       Not deleted during homeBase cleanup (every other file is deleted!)
#                       User-Changes to this file are rolled back (deleted from user overlay)
# 'bi ' = homeBase >initially< provides these files
#                       Not deleted during homeBase cleanup
#                       User-Changes are kept (NOT deleted from user overlay)

# Proper default XFCE setup
bi .config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
bi .config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml
bi .config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml

b .lapas
EOF
################################################################################
runSilentUnfallible mkdir "${LAPAS_GUESTROOT_DIR}/mnt/homeBase/.lapas";
runSilentUnfallible chown -R 1000:1000 "${LAPAS_GUESTROOT_DIR}/mnt/homeBase";
################################################################################
cat <<"EOF" > "${LAPAS_SCRIPTS_DIR}/homeFolderCleanup.sh"
#!/bin/bash

# import LAPAS config
. $(dirname "$0")/config;

pushd () { command pushd "$@" > /dev/null; }
popd () { command popd "$@" > /dev/null; }

if [ "$USER" != "root" ]; then
	echo "This has to be called as root user! Hint: use  'su - root'";
	exit 1;
# fi

# Patterns used to deselect files/folders that should be kept in the homeBase
FIND_KEEP_PATTERN_ARGS=(-not -wholename "./.keep");

# Patterns used to select the files/folders that should be cleared from the user overlay
FIND_DELETE_PATTERN_ARGS=(-wholename ""); # makes it easier with the "-or" appending

while IFS="\n" read -r patternLine; do
	patternType=$(echo "$patternLine" | awk '{print $1}');
	pattern=$(echo "$patternLine" | awk '{ st=index($0," "); print substr($0,st+1)}');

	# Append every pattern additionally with "/*" suffix, because we dont know whether its
	# a folder or a file might want to recursively keep/mask a folder and all of its contents

	# see .keep file for logic behind this
	if [ "$patternType" == "b" ]; then # delete from user overlay/workdir
		FIND_DELETE_PATTERN_ARGS+=(-or -wholename "./$pattern");
		FIND_DELETE_PATTERN_ARGS+=(-or -wholename "./$pattern/*");
	fi

	FIND_KEEP_PATTERN_ARGS+=(-and -not -wholename "./$pattern");
	FIND_KEEP_PATTERN_ARGS+=(-and -not -wholename "./$pattern/*");
done <<< $(cat "${LAPAS_GUESTROOT_DIR}/mnt/homeBase/.keep" | grep -E "^(b |bi )");

# Cleanup homeBase
echo "Cleaning up homeBase...";
pushd "${LAPAS_GUESTROOT_DIR}/mnt/homeBase" || exit 1;
	find . \( "${FIND_KEEP_PATTERN_ARGS[@]}" \) -delete 2>&1 | grep -v "Directory not empty";
popd;


function cleanupUserHome() {
	userHomeMountPoint="$1";
	shift;
	pushd "$userHomeMountPoint/upper" || return 1;
		find . \( "$@" \) -delete 2>&1 | grep -v "Directory not empty";
	popd;
}
# Cleanup user homes
echo "Cleaning up user homes...";
echo "############################################";
pushd "${LAPAS_USERHOMES_DIR}" || exit 1;
find . -type f -print0 | while read -r -d $'\0' userHome; do
	echo "- User: ${userHome:2}";
	userHomeMountPoint=$(mktemp -d);
	mount "$userHome" "$userHomeMountPoint" || exit 1;
	cleanupUserHome "$userHomeMountPoint" "${FIND_DELETE_PATTERN_ARGS[@]}";
	umount "$userHomeMountPoint" || exit 1;
done
popd;
EOF
chmod a+x "${LAPAS_SCRIPTS_DIR}/homeFolderCleanup.sh";



LAPAS_WELCOME="
The setup of your LanPArtyServer is complete. All services are up and running, no reboot is required.


\Zb===== The Guest =====\ZB
The 'guest' is the system that users of the LAPAS server (players) log into.
This is an ArchLinux installation hosted on LAPAS, that clients boot into over the network.
This guest has one base-user [name: lapas, pw: lapas, home: /mnt/homeBase].
It's homefolder is the basis of all normal users' homefolders, meaning that all files within its homefolder will 'magically appear' in all players' homefolders.
Thus, you can e.g. create wine prefixes there, and they will automatically be accessible to all players without the need to copy them to every homefolder.
The player's config files and play states are layered on top of homeBase and stored in the player's specific permanent storage.
Though if a player changes any of the files that are provided by the underlying homeBase, they will be copied into the players' permanent storage.
From then on, changes from the homeBase will not be represented in the player's homefolder anymore. (For more information, see Linux overlayfs)
Therefore, it is important that you keep this system clean. For that, the lapas user has a '.keep' file within its homefolder, that specifies \
a set of patterns and rules that should be applied during home-filesystem cleanup. (See the mentioned .keep file for more information)
This cleanup process runs automatically at every server start, so if you make changes to the homeBase, be sure to \
reboot the server and log into a normal player account, to see if it worked like you intended.
Instead of rebooting, you can also run cleanup manually on the server, using:
> cd \"${LAPAS_BASE_DIR}\"
> ./scripts/homeFolderCleanup


\Zb===== Next Step =====\ZB
Now you can boot into your guest system, by connecting a client to LAPAS' internal network and starting its network boot functionality.
The boot menu will then present you with two options:

\ZuUser\ZU
The User mode mounts your guest immutable. This is the mode meant for actual gameplay.
Any changes made to the system (apart from user home directories) will not be permanent, and only within your RAM.
So this mode is also perfect to test changes you want to make to the guest system.

\ZuAdmin\ZU
The Admin mode mounts your guest mutable. You should only boot into this when you plan to make permanent changes to the guest system \
(e.g. by installing new games, creating new wine bottles, etc.).



\Zb===== Managing Users =====\ZB
A new user has to be added before the corresponding client (that wants to use the user) boots into the guest.
This can either be done on the server:
> cd \"${LAPAS_BASE_DIR}\"
> ./scripts/addUser.sh <newUser>
Or by starting your client (User Mode), logging into the lapas user and using the Desktop shortcut.
Directly afterwards, you can then logout and switch to your user to start gaming.
In both cases, you will be asked for a password. Letting the use change their password themselfes is not possible atm. (due to the immutable filesystem).


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

#TODO:
# run home cleanup on every server start
# before dhcp!

#TODO:
# Desktop shortcut in lapas guest user to add new users (ssh to server with cert)


#TODO: keep folders without trailing / !!

#TODO In Admin mode, only lapas can login. In User Mode, everyone can login
