#!/bin/bash
if [ ! "$BASH_VERSION" ] ; then exec /bin/bash "$0" "$@"; fi


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
	dialog --erase-on-exit --title "$1" --yesno "$2" 0 0;
	if [ "$?" == "0" ]; then
		declare -g $3="yes";
	else
		declare -g $3="no";
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
runSilentUnfallible apt-get install -y dialog openssh-server ntp tftpd-hpa pxelinux samba libnfs-utils isc-dhcp-server grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin binutils nfs-kernel-server dnsmasq;

################################################
logSection "Configuration";
LAPAS_BASE_DIR=$(pwd);
LAPAS_SCRIPTS_DIR="${LAPAS_BASE_DIR}/scripts";
LAPAS_TFTP_DIR="${LAPAS_BASE_DIR}/tftp";
LAPAS_GUESTROOT_DIR="${LAPAS_BASE_DIR}/guest";
LAPAS_USERHOMES_DIR="${LAPAS_BASE_DIR}/homes";
LAPAS_TIMEZONE=$(getSystemTimezone);
LAPAS_KEYMAP=$(getSystemKeymap);
LAPAS_PASSWORD_SALT="lApAsPaSsWoRdSaLt_";

uiSelectNetworkDevices "single" "Select the upstream network card (house network / with internet connection)\nThis will be configured as dhcp client. You can change this later on if required" LAPAS_NIC_UPSTREAM || exit 1
uiSelectNetworkDevices "multi" "Select the internal lapas network card(s). If you select multiple, a bond will be created" LAPAS_NIC_INTERNAL || exit 1
uiTextInput "Input LAPAS' internal subnet (form: xxx.xxx.xxx.1/yy).\nWARNING: Old games might not handle 10.0.0.0/8 networks very well.\nWARNING:This MUST NOT collidate with your upstream network addresses." "192.168.42.1/24" "${LAPAS_SUBNET_REGEX}" LAPAS_NET_ADDRESS || exit 1
uiTextInput "Input the password you want to use for all administration accounts." "lapas" ".+" LAPAS_PASSWORD || exit 1;
LAPAS_NET_IP=${LAPAS_NET_ADDRESS%/*};
LAPAS_NET_SUBNET_BASEADDRESS="${LAPAS_NET_ADDRESS%.1/*}.0";
LAPAS_NET_NETMASK=$(netmaskFromBits ${LAPAS_NET_ADDRESS#*/});

CONFIGURATION_OVERVIEW="\
Host System:
	- Timezone: ${LAPAS_TIMEZONE}
	- Keymap: ${LAPAS_KEYMAP}
	- Locale:
$(cat /etc/default/locale | grep --invert-match -E "^#" | sed 's/^/\t  /')
	Upstream Network:
		- Adapter: ${LAPAS_NIC_UPSTREAM}
	Lapas Network:
		- Adapter(s): ${LAPAS_NIC_INTERNAL[@]}
		- Subnet Base-Address: ${LAPAS_NET_SUBNET_BASEADDRESS}
		- Lapas IP: ${LAPAS_NET_IP}
		- Lapas Netmask: ${LAPAS_NET_NETMASK}
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
LAPAS_NET_IP="${LAPAS_NET_IP}";
LAPAS_TFTP_DIR="${LAPAS_TFTP_DIR}";
LAPAS_GUESTROOT_DIR="${LAPAS_GUESTROOT_DIR}";
LAPAS_USERHOMES_DIR="${LAPAS_USERHOMES_DIR}";
LAPAS_SCRIPTS_DIR="${LAPAS_SCRIPTS_DIR}";
LAPAS_PASSWORD_SALT="${LAPAS_PASSWORD_SALT}";
LAPAS_PASSWORD_HASH="$(echo "${LAPAS_PASSWORD_SALT}${LAPAS_PASSWORD}" | sha512sum | cut -d" " -f1)";
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
option ntp-servers ${LAPAS_NET_IP};

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
runSilentUnfallible systemctl enable tftpd-hpa;
runSilentUnfallible systemctl restart tftpd-hpa;
################################################################################


logSubsection "Setting up DNS...";
################################################################################
cat <<"EOF" >> "/etc/dnsmasq.conf"
# enable DNS on our internal lapas bond network
interface=lapas
# disable DHCP / TFTP (dnsmasq is a little too weak for our dhcp needs)
no-dhcp-interface=
EOF
runSilentUnfallible systemctl enable dnsmasq;
runSilentUnfallible systemctl restart dnsmasq;
################################################################################


logSubsection "Setting up NFS...";
################################################################################
cat <<EOF > "/etc/exports"
${LAPAS_GUESTROOT_DIR} *(rw,no_root_squash,async,no_subtree_check)
${LAPAS_USERHOMES_DIR} *(rw,no_root_squash,async,no_subtree_check)
EOF
runSilentUnfallible exportfs -ra;
runSilentUnfallible systemctl enable rpc-statd;
runSilentUnfallible systemctl restart rpc-statd;
################################################################################


logSubsection "Setting up NTP...";
runSilentUnfallible systemctl enable ntp;
runSilentUnfallible systemctl restart ntp;



logSection "Setting up Guest OS (Archlinux)...";
################################################
# see: https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#From_a_host_running_another_Linux_distribution
pushd "${LAPAS_GUESTROOT_DIR}";
	logSubsection "Downloading Archlinux Bootstrap..."
	wget https://ftp.fau.de/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.gz || exit 1;
	logSubsection "Preparing Archlinux Bootstrap..."
	runSilentUnfallible tar xzf archlinux-bootstrap-x86_64.tar.gz --strip-components=1 --numeric-owner
	rm archlinux-bootstrap-x86_64.tar.gz;
popd;
runSilentUnfallible mount -o bind "${LAPAS_GUESTROOT_DIR}" "${LAPAS_GUESTROOT_DIR}";

echo "${LAPAS_GUESTROOT_DIR} ${LAPAS_GUESTROOT_DIR} none defaults,bind 0 0" >> "/etc/fstab";

# setup guest by initializing software repository (enable multilib for wine)
echo 'Server = http://ftp.fau.de/archlinux/$repo/os/$arch' >> "${LAPAS_GUESTROOT_DIR}/etc/pacman.d/mirrorlist";
echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> "${LAPAS_GUESTROOT_DIR}/etc/pacman.conf";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman-key --init;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman-key --populate archlinux;

# installing dependencies
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman -Syu --noconfirm;
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" pacman --noconfirm -S nano base-devel bc wget \
	mkinitcpio mkinitcpio-nfs-utils linux-firmware nfs-utils \
	xfce4 xfce4-goodies gvfs xorg-server lightdm lightdm-gtk-greeter pulseaudio pulseaudio-alsa pavucontrol aoss \
	firefox geany file-roller openbsd-netcat \
	wine-staging winetricks zenity \
	lib32-libxcomposite lib32-libpulse || exit 1;

# configure locale and time settings
# TODO: Ugh... debian11 does not yet have systemd-firstboot in its distro (about to change in the future, bug already fixed).
# refactor this manual stuff to systemd-firstboot --root="<guest>" --copy
cat /etc/default/locale | sed -r 's/^\w+="(.*)"/\1/g' | sed -n '/^.*_.*\..*/p' | uniq >> "${LAPAS_GUESTROOT_DIR}/etc/locale.gen";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" locale-gen;
#runSilentUnfallible cp "/etc/default/locale" "${LAPAS_GUESTROOT_DIR}/etc/default/locale";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemd-firstboot --force --timezone="${LAPAS_TIMEZONE}" \
	--root-password="${LAPAS_PASSWORD}" --setup-machine-id --hostname="guest";
################################################################################
# Set keymap with init service instead, because it then also creates the x11 keymap
cat <<EOF > "${LAPAS_GUESTROOT_DIR}/etc/systemd/system/lapas-firstboot-setup.service"
[Unit]
ConditionPathExists=!/lapas/.firstbootSetup
Before=multi-user.target display-manager.service

[Service]
Type=oneshot
ExecStart=localectl set-keymap ${LAPAS_KEYMAP}
ExecStart=timedatectl set-ntp true
ExecStartPost=/usr/bin/touch /lapas/.firstbootSetup
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-firstboot-setup;
################################################################################

	
#Prepare global folder for lapas-stuff
runSilentUnfallible mkdir "${LAPAS_GUESTROOT_DIR}/lapas";


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
	uiYesNo "Kernel Config" "[Expert Only]\nI configured your guest kernel with my config. Do you want to make any further changes to the config before I start compiling?" resultSpawnMenuconfig;
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
"${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" bash -c "yes \"${LAPAS_PASSWORD}\" | passwd lapas" || exit 1;
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}/mnt/homes";
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}/mnt/.overlays";
################################################################################
cat <<EOF >> "${LAPAS_GUESTROOT_DIR}/etc/fstab"
${LAPAS_NET_IP}:${LAPAS_USERHOMES_DIR}      /mnt/homes      nfs     defaults,nofail 0 0
EOF
################################################################################
# When starting in user mode, this service runs the cleanup process as specified by the homeBase/.keep file.
# All users (lapas, as well as players) thus will then have a cleaned homeBase as base for their homeFolder.
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/etc/systemd/system/lapas-filesystem.service"
[Unit]
Description="Prepares the LAPAS guest filesystem"
ConditionPathExists=/.lapasUser
DefaultDependencies=no
After=local-fs-pre.target
Before=local-fs.target

[Service]
Type=oneshot
ExecStart=/lapas/initCleanHomeBase.sh
RemainAfterExit=yes

[Install]
RequiredBy=local-fs.target
EOF
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/arch-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-filesystem;
################################################################################
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/lapas/initCleanHomeBase.sh"
#!/bin/bash

USER_BASE="/mnt/homeBase";

. /lapas/common.sh || exit 1;
. /lapas/parseKeepPatterns.sh || exit 1;

echo "Applying cleanup with keep patterns to overlay (transform homeBase -> cleanHomeBase)";
assertSuccessfull pushd "${USER_BASE}";
        assertSuccessfull find . \( "${FIND_KEEP_PATTERN_ARGS[@]}" \) -delete;
assertSuccessfull popd;
EOF
runSilentUnfallible chmod a+x "${LAPAS_GUESTROOT_DIR}/lapas/initCleanHomeBase.sh";
################################################################################
cat <<EOF >> "${LAPAS_GUESTROOT_DIR}/etc/pam.d/system-login"
session       required   pam_exec.so          stdout /lapas/mountHome.sh
EOF
################################################################################
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/lapas/parseKeepPatterns.sh"
#!/bin/bash

# Patterns used to deselect files/folders that should be kept in the homeBase
export FIND_KEEP_PATTERN_ARGS=(-not -wholename "./.keep");

# Patterns used to select the files/folders that should be cleared from the user overlay
export FIND_DELETE_PATTERN_ARGS=(-wholename ""); # makes it easier with the "-or" appending

while IFS="\n" read -r patternLine; do
        patternType=$(echo "$patternLine" | awk '{print $1}');
        pattern=$(echo "$patternLine" | awk '{ st=index($0," "); print substr($0,st+1)}');

        # Append every pattern additionally with "/*" suffix, because we dont know whether its
        # a folder or a file might want to recursively keep/mask a folder and all of its contents

        # see .keep file for logic behind this
        if [ "$patternType" == "b" ]; then # delete from user overlay/workdir
                FIND_DELETE_PATTERN_ARGS+=(-or -wholename "'./$pattern'");
                FIND_DELETE_PATTERN_ARGS+=(-or -wholename "'./$pattern/*'");
        fi

        FIND_KEEP_PATTERN_ARGS+=(-and -not -wholename "'./$pattern'");
        FIND_KEEP_PATTERN_ARGS+=(-and -not -wholename "'./$pattern/*'");
done <<< $(cat "/mnt/homeBase/.keep" | grep -E "^(b |bi )");
EOF
################################################################################
#!/bin/bash
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/lapas/common.sh"
function assertSuccessfull() {
        echo "Running: $@";
        $@;
        resultCode="$?";
        if [ "$resultCode" == 0 ]; then return 0; fi
        echo "Command: > $@ < exited unexpectedly with error code: $resultCode";
        echo "Aborting...";
        exit $resultCode;
}
export -f assertSuccessfull;
EOF
################################################################################
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/lapas/mountHome.sh"
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

echo "[LOGON] Login user: $PAM_USER, home: $USER_HOME";
USER_HOME=$(getent passwd $PAM_USER | cut -d: -f6);

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

                # Run user upper-dir cleanup
                . /lapas/parseKeepPatterns.sh || exit 1;
                assertSuccessfull pushd "$USER_IMAGE_MOUNTDIR/upper";
                        assertSuccessfull find . \( "${FIND_DELETE_PATTERN_ARGS[@]}" \) -delete 2>&1 | grep -v "Directory not empty";
                assertSuccessfull popd;
        fi
        if [ $(mount | grep "$USER_HOME" | wc -l) == 0 ]; then
                assertSuccessfull mkdir -p "$USER_HOME";
                assertSuccessfull chown -R $PAM_USER:lanparty "$USER_HOME";
                assertSuccessfull mount -t overlay overlay -o lowerdir="${USER_BASE}",upperdir="${USER_IMAGE_MOUNTDIR}/upper",workdir="${USER_IMAGE_MOUNTDIR}/work" "$USER_HOME";
        fi
fi
EOF
runSilentUnfallible chmod a+x "${LAPAS_GUESTROOT_DIR}/lapas/mountHome.sh";
################################################################################
echo "nameserver ${LAPAS_NET_IP}" >> "${LAPAS_GUESTROOT_DIR}/etc/resolv.conf";
echo "NTP=${LAPAS_NET_IP}" >> "${LAPAS_GUESTROOT_DIR}/etc/systemd/timesyncd.conf";
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
# These are initially provided from the homeBase, but players can make permanent changes for themselves
bi .config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
bi .config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml
bi .config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml

# Application starters
b .local/share/applications

# This folder contains lapas specific stuff and is >always< supplied from the homeBase.
b .lapas

# Example: Wine games [here, homeBase should not provide user-specific stuff like user.reg]
#b .wineprefixes/*/drive_c
#b .wineprefixes/*/dosdevices
#b .wineprefixes/*/.update-timestamp
#b .wineprefixes/*/system.reg
EOF
################################################################################
runSilentUnfallible mkdir "${LAPAS_GUESTROOT_DIR}/mnt/homeBase/.lapas";
cat <<"EOF" > "${LAPAS_GUESTROOT_DIR}/mnt/homeBase/.lapas/addUser.sh"
#!/bin/bash
if [ ! "$BASH_VERSION" ]; then exec /bin/bash "$0" "$@"; fi

LAPAS_API_IP=$(ip route | grep "default via" | cut -d' ' -f3);
LAPAS_API_PORT=1337;

function handleNewUser() {
	while true; do
		IFS='|' CREDS=( $(zenity --forms --title "Add User" --text "Add new user" \
			--add-entry="Username" \
			--add-password="Password" \
			--add-password="Password Confirm"$) );
		if [ $? != 0 ]; then exit 0; fi
		if [ "${CREDS[0]}" == "" ]; then
			zenity --error --title="Invalid Input" --text="Username must not be empty";
			continue;
		fi
		if [ "${CREDS[1]}" == "" ]; then
			zenity --error --title="Invalid Input" --text="Password must not be empty";
			continue;
		fi
		if [ "${CREDS[1]}" != "${CREDS[2]}" ]; then
			zenity --error --title="Invalid Input" --text="Password repetition does not match password!";
			continue;
		fi
		break;
	done
	echo "addUser";
	echo "${CREDS[0]}";
	echo "${CREDS[1]}";
	read addUserResult;
	if [ "${addUserResult:0:2}" != "0 " ]; then
		zenity --error --title="Server Error" --text="Adding user failed:\n${addUserResult}";
		return 1;
	fi
}

while true; do
	# Connect to server API and authenticate
	while true; do
		lapasPassword=$(zenity --password --title="Lapas Auth");
		if [ $? != 0 ]; then exit 0; fi

		echo "Connecting to LAPAS API...";
		coproc client { nc ${LAPAS_API_IP} ${LAPAS_API_PORT}; }
		
		echo "$lapasPassword" >&${client[1]};
		read authResult <&${client[0]};
		if [ "${authResult:0:2}" == "0 " ]; then break; fi
		
		zenity --error --title="Authentication Error" --text="Authentication failed: ${authResult}";
		exec {client[1]}>&-; # close stream
		wait "${client_PID}";
	done

	handleNewUser <&${client[0]} >&${client[1]};
	if [ "$?" == 0 ]; then
		exec {client[1]}>&-; # close stream
		break;
	fi
done
EOF
runSilentUnfallible chown -R 1000:1000 "${LAPAS_GUESTROOT_DIR}/mnt/homeBase";
################################################################################
cat <<"EOF" > "${LAPAS_SCRIPTS_DIR}/addUser.sh"
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
EOF
################################################################################
cat <<"EOF" > "${LAPAS_SCRIPTS_DIR}/apiServer.sh"
#!/bin/bash
if [ ! "$BASH_VERSION" ]; then exec /bin/bash "$0" "$@"; fi

# import LAPAS config
. $(dirname "$0")/config;

function handleClient() {
        1>&2 echo "Awaiting authentication...";
        read authPassword || return 1;
        authPasswordHash=$(echo "${LAPAS_PASSWORD_SALT}${authPassword}" | sha512sum | cut -d" " -f1);
        if [ "$LAPAS_PASSWORD_HASH" != "$authPasswordHash" ]; then
                1>&2 echo "Authentication failed... closing connection";
                echo "1 Auth failed (wrong password)"; return 1;
        fi
        echo "0 Auth Ok";

        1>&2 echo "Authentication successful. Waiting for command...";
        read COMMAND || return 1;
        if [ "$COMMAND" == "addUser" ]; then
                1>&2 echo "Handling: addUser";
                read newUsername || return 1;
                read newPassword || return 1;
                if [ "$newPassword" == "" ]; then
                        echo "3 Command Failed (empty password not allowed)"; return 1;
                fi
                ADDUSER_LOG=$($(dirname "$0")/addUser.sh "$newUsername" "$newPassword" 2>&1);
                if [ $? != 0 ]; then
                        1>&2 echo "Adding user ${newUsername} failed: ${ADDUSER_LOG}";
                        echo "3 Command Failed (${ADDUSER_LOG})"; return 1;
                fi
                1>&2 echo "Added user: ${newUsername}";
                echo "0 Success"; return 0;
        else
                1>&2 echo "Received unknown command: ${COMMAND}";
                echo "2 Unknown command"; return 1;
        fi
};
export -f handleClient;

while true; do
        echo "Waiting for API client...";
        coproc serv { nc -q0 -lp 1337; }
        handleClient <&${serv[0]} >&${serv[1]};
        # close our outgoing stream
        exec {serv[1]}>&-;
        echo "Disconnected.";
        sleep 1000;
        echo "###########################";
done
EOF
chmod a+x "${LAPAS_SCRIPTS_DIR}/apiServer.sh";
################################################################################
cat <<EOF > "/etc/systemd/system/lapas-api-server.service"
[Unit]
After=network.target

[Service]
Type=simple
ExecStart=${LAPAS_SCRIPTS_DIR}/apiServer.sh

[Install]
WantedBy=multi-user.target
EOF
################################################################################
runSilentUnfallible systemctl daemon-reload;
runSilentUnfallible systemctl enable lapas-api-server;
runSilentUnfallible systemctl start lapas-api-server;



LAPAS_WELCOME="
The setup of your LanPArtyServer is complete. All services are up and running, no reboot is required.


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
