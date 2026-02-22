#!/bin/bash
if [ ! "$BASH_VERSION" ] ; then exec /bin/bash "$0" "$@"; fi
SELF_PATH=$(realpath "$0");


# CONSTANTS
##############################
LAPAS_SUBNET_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,3}$";
MAC_REGEX="(?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2})";
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
		
		Installer v2.0
	";
}

#!import helpers/logging.sh
#!import helpers/process.sh
#!import helpers/system.sh
#!import helpers/arrays.sh
#!import helpers/ipcalc.sh
#!import helpers/opensuse.sh

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
runSilentUnfallible apt-get install -y curl jq dialog ethtool gdisk dosfstools openssh-server chrony pxelinux libnfs-utils binutils nfs-kernel-server targetcli-fb dnsmasq restic;
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

# underlay root filesystem moutpoint when booting in user(read-only) mode.
LAPAS_GUESTIMG_PATH="${LAPAS_BASE_DIR}/guest.img";
LAPAS_GUESTIMG_SIZE="1T";
LAPAS_GUESTIMG_FSUUID="16d4a517-bf5d-45f3-8fd3-92f1edcb613e";
LAPAS_GUESTIMG_NAME="lapas_guest";
LAPAS_GUESTIMG_IQN="iqn.1970-01.lapas.lapas:guest";
LAPAS_GUESTIMG_LUN="0";

# make sure bash arrays are printed space separated
IFS=' ';
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
	"LAPAS_GUESTIMG_RO_MOUNTPOINT"="${LAPAS_GUESTIMG_RO_MOUNTPOINT}"
	"LAPAS_GUESTIMG_PATH"="${LAPAS_GUESTIMG_PATH}"
	"LAPAS_GUESTIMG_SIZE"="${LAPAS_GUESTIMG_SIZE}"
	"LAPAS_GUESTIMG_FSUUID"="${LAPAS_GUESTIMG_FSUUID}"
	"LAPAS_GUESTIMG_NAME"="${LAPAS_GUESTIMG_NAME}"
	"LAPAS_GUESTIMG_IQN"="${LAPAS_GUESTIMG_IQN}"
	"LAPAS_GUESTIMG_LUN"="${LAPAS_GUESTIMG_LUN}"
);

cliYesNo "This is your configuration. Continue?" resultConfigCheckOk;
if [ "$resultConfigCheckOk" == "no" ]; then
	logInfo "Aborting...";
	exit 1;
fi


################################################################################################
logSection "Setting up Guest Disk";
################################################################################################
# Prepare sparse ext4 formatted disk image as guest disk
runSilentUnfallible truncate -s ${LAPAS_GUESTIMG_SIZE} ${LAPAS_GUESTIMG_PATH};
runSilentUnfallible mkfs.ext4 -U ${LAPAS_GUESTIMG_FSUUID} ${LAPAS_GUESTIMG_PATH};
targetcli <<EOF
	clearconfig true
	
	# Create fileio backstore
	/backstores/fileio create ${LAPAS_GUESTIMG_NAME} ${LAPAS_GUESTIMG_PATH} ${LAPAS_GUESTIMG_SIZE} write_back=true sparse=true
	
	# Create iSCSI target
	/iscsi create ${LAPAS_GUESTIMG_IQN}
	
	# Create LUN
	/iscsi/${LAPAS_GUESTIMG_IQN}/tpg1/luns create /backstores/fileio/${LAPAS_GUESTIMG_NAME} lun=$LAPAS_GUESTIMG_LUN
	
	# Enable TPG attributes
	# - No authentication
	# - Allow unauthenticated read-write
	# - Auto-generate ACLs for any initiator
	/iscsi/${LAPAS_GUESTIMG_IQN}/tpg1 set attribute authentication=0 demo_mode_write_protect=0 generate_node_acls=1
	
	# store config
	saveconfig
EOF
# mount image for all following tasks
runSilentUnfallible mkdir "${LAPAS_GUESTROOT_DIR}";
runSilentUnfallible mount "${LAPAS_GUESTIMG_PATH}" "${LAPAS_GUESTROOT_DIR}";


################################################################################################
logSection "Preparing Guest OS (openSUSE Tumbleweed base image)...";
################################################################################################
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}";
pushd "${LAPAS_GUESTROOT_DIR}";
	logSubsection "Downloading openSUSE Tumbleweed Bootstrap...";
	OPENSUSE_IMG_NAME=$(getOpenSuseTumbleweedImgName);
	wget https://download.opensuse.org/tumbleweed/appliances/${OPENSUSE_IMG_NAME} || exit 1;
	logSubsection "Preparing openSUSE Tumbleweed Bootstrap...";
	runSilentUnfallible tar -x -f ${OPENSUSE_IMG_NAME} --numeric-owner;
	runSilentUnfallible rm ${OPENSUSE_IMG_NAME};
popd;


################################################################################################
logSection "Extracting LAPAS resources..."
################################################################################################
streamBinaryPayload "${SELF_PATH}" "__PAYLOAD_LAPAS_RESOURCES__" | base64 -d | gzip -d | tar -x --no-same-owner || exit 1;
runSilentUnfallible configureOptionsToFile "${LAPAS_SCRIPTS_DIR}/config" "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace "${LAPAS_GUESTROOT_DIR}/etc/fstab" "${LAPAS_CONFIGURATION_OPTIONS[@]}";
runSilentUnfallible configureFileInplace "${LAPAS_GUESTROOT_DIR}/etc/resolv.conf" "${LAPAS_CONFIGURATION_OPTIONS[@]}";
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

logSubsection "Setting up locale and time settings"
runSilentUnfallible systemd-firstboot --root="${LAPAS_GUESTROOT_DIR}" --reset --force --copy --setup-machine-id --root-password="${LAPAS_PASSWORD}" --hostname="guest";

# Need working DNS resolution in guest, but lapas dnsmasq is not working yet,
# so temporarily override guest's resolve.conf
echo "nameserver 8.8.8.8" | pushFileOverride "${LAPAS_GUESTROOT_DIR}/etc/resolv.conf" || exit 1;


################################################################################################
logSection "Setting up Guest OS (installing software)"
################################################################################################
logSubsection "Installing base system";
runUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" zypper addlock -t package wicked-service firewalld yast2;
runUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" zypper install -y -l --force-resolution \
	branding-upstream grub2 grub2-x86_64-efi grub2-i386-pc shim dracut open-iscsi iscsiuio systemd-sysvinit \
	kernel-default patterns-base-base systemd-resolved nfs-client;

logSubsection "Installing Software";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" zypper addlock -t pattern kde_internet kde_pim kde_games kde_office kde_yast games office;
runUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" zypper --non-interactive addrepo --refresh https://download.opensuse.org/repositories/games/openSUSE_Tumbleweed/games.repo;
runUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" zypper --non-interactive --gpg-auto-import-keys refresh;
runUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" zypper install -y -l --force-resolution \
	patterns-kde-kde gstreamer-plugins-bad gstreamer-plugins-ugly \
	bindfs nano autorandr zenity libnotify-tools wine-staging umu-launcher;

################################################################################################
logSection "Setting up Guest OS Network Settings..."
################################################################################################
# use systemd-resolvd (enables us to use resolvectl)
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl disable ModemManager;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable systemd-resolved;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable iscsid;
echo "NTP=${LAPAS_NET_IP}" >> "${LAPAS_GUESTROOT_DIR}/etc/systemd/timesyncd.conf";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable sshd;

################################################################################################
logSection "Setting up Guest OS Services>..."
################################################################################################
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-firstboot-setup;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-filesystem;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" systemctl enable lapas-api-daemon;
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}/mnt/homes";

# configure lapas api daemon authentification
runSilentUnfallible mkdir -p "${LAPAS_GUESTROOT_DIR}/lapas";
echo "API_PASSWORD=\"${LAPAS_PASSWORD}\"" > "${LAPAS_GUESTROOT_DIR}/lapas/lapas-api.env";
runSilentUnfallible chmod a-rwx "${LAPAS_GUESTROOT_DIR}/lapas/lapas-api.env";

logSubsection "Setting up UI, User & Home System"
# configuring pam service to manage user homefolders for players
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" pam-config --add --exec;

##############################################
# setup base user
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" groupadd --gid 1000 lanparty;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" useradd --gid lanparty --home-dir /mnt/homeBase --create-home --uid 1000 lapas;
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" "echo lapas:\"${LAPAS_PASSWORD}\" | chpasswd";
# setup lapas user management
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" install -m 0644 /libnss_lapas.so.2 /usr/lib64;
rm "${LAPAS_GUESTROOT_DIR}/libnss_lapas.so.2";
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" /sbin/ldconfig -n /lib /usr/lib;


################################################################################################
logSection "Setting up Guest OS Boot Process";
################################################################################################
# use openSUSE's signed grub, because the kernel's signature has to match the grub's signature.
# We setup grub2 inside the guest once, then move that out and don't touch it anymore.
runSilentUnfallible "${LAPAS_GUESTROOT_DIR}/bin/suse-chroot" "${LAPAS_GUESTROOT_DIR}" grub2-mknetdir --net-directory /boot --subdir=grub2;
runSilentUnfallible mv "${LAPAS_GUESTROOT_DIR}/boot/grub2" "${LAPAS_TFTP_DIR}/";
runSilentUnfallible ln -s -r "${LAPAS_TFTP_DIR}/grub2/grub.cfg" "${LAPAS_TFTP_DIR}/grub.cfg";

# setup boot menu and install kernel/ramdisk
runSilentUnfallible cp -aLR "${LAPAS_GUESTROOT_DIR}/boot" "${LAPAS_TFTP_DIR}/boot";
runSilentUnfallible "${LAPAS_SCRIPTS_DIR}/updateBootmenus.sh";

##############################################
# finalize work on guest (unmount image)
popFileOverride "${LAPAS_GUESTROOT_DIR}/etc/resolv.conf" || exit 1;
runSilentUnfallible umount "${LAPAS_GUESTROOT_DIR}";
runSilentUnfallible rmdir "${LAPAS_GUESTROOT_DIR}";




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
runSilentUnfallible mkdir -p "/srv/nfs/homes";
echo "${LAPAS_USERHOMES_DIR} /srv/nfs/homes none bind 0 0" >> "/etc/fstab" || exit 1;
runSilentUnfallible systemctl daemon-reload;
runSilentUnfallible mount -o bind "${LAPAS_USERHOMES_DIR}" "/srv/nfs/homes";
runSilentUnfallible exportfs -ra;
runSilentUnfallible systemctl restart nfs-kernel-server;


logSubsection "Setting up NTP...";
################################################################################
runSilentUnfallible systemctl enable chrony;


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

runSilentUnfallible systemctl restart chrony;
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
