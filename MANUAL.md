---
title: 'How to build a Linux-based LAN-Party Server'
lang: 'en_GB'
---

# Preview
LAN-Parties are a nice way of having fun with a couple of like-minded people, enjoying some old game classics. But every LAN-Party comes with its share of problems:
One is the incompatibility between setups. We often had the problem, that new Windows versions are unable to run the really old classics, while executing them via **wine** is working flawlessly.
Another is the problem with games storing a multiplayer-progress. When one of the members reinstalls their system, these progress files are often gone - creating the need to start the story anew. Playing the same story-part on every LAN is not that thrilling.
The most frequent problem, however, is the distribution of (legal!) game copies to the machines of all members that deleted the game ("because there was no space left"), or because of reinstallations.

Some day, we began thinking about how one could solve these problems. One idea was, that every member gets a USB-Stick with all of the games and his progress-files on it. But distributing updates and new games would still be a nightmare, let alone copying the progress-files (which are stored somewhere in the personal files folder) onto the stick after each LAN. So that's not an option!

## The idea
With a bit of inspiration from god knows where, an idea popped up. How about a "LAN-Party OS", that is network-booted from a server where all games are set up, ready to go? **LA**n**PA**rty**S**erver, or **LAPAS** was born.

Every user needs his own home folder, that contains his game-progress data. But since the games (especially for PlayOnLinux and Wine) need to be in the home folder, we would have to clone all the games for every user. That's definitely not feasible - and this is where `overlayfs` comes in. So what we do is move all the shared data between users into what we will be referring to as `homeBase`. When a user logs in, we will create his actual home folder using overlayfs with `homeBase` as underlay and a writeable home-folder on the server as overlay.
Unfortunately, wine requires the executing user to actualy own the wineprefix he's executing from (correct userId). This makes sharing exactly this data quite hard. We solved this using a small hack: every lanparty user has the same uid (1000). So this setup is probably not that well-fitted for parties where you don't trust the users.
Another problem that arose was, that NFS can not be used as the upper side of an `overlayfs`. Due to this, another hack was necessary, detailed in the user-home setup part.

## The architecture
``` mermaid
graph BT
    lapas(LAPAS); nic0; nic1;
    lapas --> nic0
    lapas --> nic1

    nic0 --> dhcpClient(DHCP-Client)
    
    nic1 --> tftpServer(TFTP-Server)
    tftpServer --> kernelImage(Kernel-Image)
    tftpServer --> ramdiskImage(RamDisk)
    
    nic1 --> nfsServer(NFS-Server)
    nfsServer --> guestRoot(Guest-Root)
    nfsServer --> baseHome(User HomeBase)
    nfsServer --> overlayHome(writeable User-Home)
    baseHome -- overlayfs --> overlayHome
    
    nic1 --> dhcpServer(DHCP-Server)
    dhcpServer --> tftpLink(TFTP-Address)
```
The whole construct consists of two parts, the server and the so-called **guest**. The guest is the operating system that can be netbooted from the server.

LAPAS will provide a **TFTP** server for the network boot procedure. For this, a kernel image and a ramdisk image, as well as a bootloader will be hosted.

LAPAS will also run a **DHCP** server, to provide ip addresses for all users. Additionally, the DHCP-Server has to tell every machine where it can find the tftp server for the netbooting procedure. For this, the DHCP server tells a client the address of the tftp server and a path on the tftp-server to the bootloader-executable that it should download and execute.

Another server that LAPAS will provide is a **NFS** server. This will host multiple things:
- The guest's rootfs, also countaining our `homeBase`.
- A mount we call `homefolders`, where all the users' dynamic data will reside

So the folder structure exported looks something like the following:
``` mermaid
graph BT
    lapas(LAPAS nfs) --> rootfs
    rootfs --> rootfsUsr(/usr)
    rootfs --> rootfsLib(/lib)
    rootfs --> rootfsEtc(/...)
    rootfs --> rootfsHomeBase(/mnt/homeBase)
    lapas --> homefolders
    homefolders --> user0
    homefolders --> user1
    homefolders --> user2
```

In normal operation, the **guest**'s root filesystem is read-only. But since that would cause issues, we overlay (`overlayfs`) its root filesystem with a temporary filesystem (`tmpfs`), where each guest can do changes to its root filesystem - albeit only locally in the guest computer's RAM, and only temporary.

# Setting up the Server
For our server, we are using openSUSE Tumbleweed. Some of the steps are not documented by commandlines or config-files, because they were configured through openSUSE's YaSt. So following the instructions below will be easiest using the same setup.
If you insist on using something else, you probably know what you're doing anyway.

## Configuring Services

### Network
For the network setup, you need at least 2 NICs.
- **nic0** will be the network interface to the house network (if any). That one should probably be using DHCP to be able to fit into any house network.
- **nic1** is the interface that will be serving the users. On this nic, we have to set a static ip address. In the following guide, I will be using `192.168.42.1` with a netmask of `255.255.255.0` for this.

:::danger
**Note:**
- Do not connect **nic1** to your home network, because we will later be running a DHCP server on it.
- I originally chose `10.13.37.1` as address, though some of the older games seem to have problems with that. So it's best to stick with `192.168.*`.
:::

Also enable forwarding on the server, so guests can access the internet through the server.

### TFTP-Server
For other users to be able to boot from lapas, we will have to setup a TFTP server. There's not much more to configure than a location from where files are served: `/mnt/data/tftp` in our case. On openSUSE, configure this using `YaSt -> Network Services -> TFTP Server`

### DHCP-Server
For the DHCP-Server, there's a bit more to configure. This is mainly because we want to support UEFI and BIOS machines as guests.
We will be using the ISC DHCP Server. To install this under openSUSE, run the following:
```bash
$> zypper install dhcp-server
```
Next, configure the server to work on the internal **nic1** interface (e.g. with YaSt), and use the following rules config-file (`/etc/dhcpd.conf`): 
```=
allow booting;
allow bootp;

option architecture-type code 93 = unsigned integer 16;
option domain-name-servers 192.168.42.1;
option routers 192.168.42.1;

ddns-update-style none;
default-lease-time 86400;

group {
        if option architecture-type = 00:06 or option architecture-type = 00:07 {
                filename "grub2/x86_64-efi/core.efi";
        } else {
#               filename "grub2/i386-pc/core.0";
                filename "bios/pxelinux.0";
        }

        next-server 192.168.42.1;
        subnet 192.168.42.0 netmask 255.255.255.0 {
          range dynamic-bootp 192.168.42.30 192.168.42.230;
          default-lease-time 86400;
          max-lease-time 172800;
        }
}
```
When requesting an address, a DHCP-Client tells the server some information about itself. Interesting for the netboot-server is, whether a client is based on UEFI or BIOS, because we have to decide what we want him to boot based on that (that is what the if-else block is about).

### NFS-Server
The NFS-Server will host the rootfs of the guest OS. For the OS, we will be using Archlinux. In our case, this rootfs will be in `/mnt/data/guest`. The guest's kernel will support booting directly from an NFS-share. However, this only works with NFSv3 and below, so we will disable NFSv4 and all the security and identification stuff. We use the following export-options:
`rw,async,no_root_squash,no_subtree_check`

For the user-home architecture, we need a share that will contain the dynamic data (game-stats, desktop settings, ...) of every user. So we will add another nfs export for `/mnt/data/homes`, with the options:
`rw,async,no_root_squash,no_subtree_check`

On openSUSE, install the package `yast2-nfs-server`, and run the nfs config in YaSt, configuring the mentioned paths.
This makes `/etc/exports` look something like the following in the end:
```=
/mnt/data/guest *(rw,no_root_squash,async,no_subtree_check)
/mnt/data/homes *(rw,no_root_squash,async,no_subtree_check)
```

## TFTP-Folder
Since we want to support UEFI and BIOS, we will use GRUB as bootloader. The easiest way to do this is on a distribution, where it's already installed.
There, you should have a `grub2-mknetdir` executable, which does exactly what we want in a single commandline:
```bash
$> grub2-mknetdir --net-directory=/mnt/data/tftp/ --subdir=grub2
```
This generates us a configured and bootable grub2 setup into the `/mnt/data/tftp/grub2`-folder.

:::warning
**Note:**
What architectures are supported by the generated folder depends on the architectures that were installed by your distribution. In other words: The architecture-type of your server will definitely be supported, but for others you will have to install extra grub2 platforms. Under openSUSE e.g. via the package `grub2-x86_64-efi` to support 64bit UEFI.
Our example uses the two platforms: `i386-pc` and `x86_64-efi`
:::

Your tftp-folder structure should now look something like the following:
``` mermaid
graph BT
    tftpRoot(tftp-root - /mnt/data/tftp)
    tftpRoot --> grub2
    grub2 --> fonts
    grub2 --> i386-pc
    grub2 --> locale
    grub2 --> x86_64-efi
```

Now we need to tell grub2 *what* to boot. For this, we add a new `grub.cfg` file within the `grub2` folder in the tftp-root (`/mnt/data/tftp/`). The file (`/mnt/data/tftp/grub2/grub.cfg`) will have the following content:
```=
set default="0"
set timeout=5

menuentry 'User' {
        linux /bzImage ip=dhcp init=/lib/systemd/systemd
        initrd /ramdisk.img
}

menuentry 'Admin' {
        linux /bzImage ip=dhcp root=/dev/nfs rw nfsroot=192.168.42.1:/mnt/data/guest,vers=3 init=/lib/systemd/systemd
}
```
This defines two possible boot options.
- `Admin` will mount the rootfs writeable, making it possible to do changes to the guest (file-)system.
- `User`, which is meant for normal operation, will not be able to do any permanent changes to the rootfs of the guest. This is achieved by using an overlayfs early on in the boot (which is why this option needs a ramdisk)

## Test it
This is a good point where you should probably test if your netbooting works. Connect a pc to **nic1** of your server, open the boot menu and try network booting. You should now see a grub menu showing the two entries `User` and `Admin` from above. Note that none of both will work at this point.

## Setting up the guest
Now we install our Archlinux-based guest rootfs in `/mnt/data/guest`, mostly following [this guide](https://wiki.archlinux.org/index.php/Install_from_existing_Linux#Method_A:_Using_the_bootstrap_image_.28recommended.29):
```bash=
# switch to guest's rootfs folder
cd /mnt/data/guest

# download the newest bootstrap image
# (find a new image through: https://www.archlinux.org/download/)
wget https://ftp.fau.de/archlinux/iso/latest/archlinux-bootstrap-YYYY.MM.DD-x86_64.tar.gz

# extract to current folder
tar xzf archlinux-bootstrap-*-x86_64.tar.gz

# move out of subfolder
mv root.x86_64/* ./
rm root.x86_64/ -r

# select mirror by uncommenting a line in:
nano ./etc/pacman.d/mirrorlist

# chroot into the guest image
./bin/arch-chroot ./
mount --bind / /
exit
./bin/arch-chroot ./

# initializing software repository
pacman-key --init
pacman-key --populate archlinux
pacman -Syu

# install some basic stuff
pacman -S nano

# set timezone (Europe/Berlin in our example)
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

# configure locale settings
localectl set-locale LANG=en_US.UTF-8

# configure keymaps (e.g. german):
localectl set-keymap de
localectl set-x11-keymap de 

# set hostname to "guest" (optional)
echo "guest" > /etc/hostname

# set the root password for within the guest OS
passwd
```

The base system of our guest is now set up. Since we have some weird requirements for our guest kernel to work, we have to build it ourselves:

### Compiling a Kernel
:::danger
**Note:**
- The kernel needs support for booting from NFS-shares
- The kernel needs support for overlayfs
- Since we have a network drive as root filesystem, we need the kernel to hav NIC drivers early on in the boot process, so the drivers for all network cards you need support for on the guest machines have to be compiled into the kernel, instead of modules loaded at runtime. This is what disqualifies most of the normal distribution kernels.
- ... probably more
:::
For the reasons mentioned above, we will compile our own kernel for the guest. To start building your own kernel (we are still chrooted in our guest!), do the following:
```bash=
# install build essentials so we can compile our own kernel
pacman -S base-devel bc wget

# fetch some current kernel from kernel.org, and untar it
cd /usr/src/
# (search for the newest version here: https://cdn.kernel.org/pub/linux/kernel/)
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.14.21.tar.gz
tar xvf linux*.tar.gz
cd ./linux-5.14.21
```
If you're really into it, you can use your own knowledge or [this](https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Kernel#Default:_Manual_configuration) guide from the Gentoo Wiki to build your own kernel.

But in case you've never built a kernel, and don't want to dig your nose that deep in, you can find the kernel configuration file we are using [here](https://hastebin.com/zoyahowoyu.shell). To use it, change into the folder you just extracted from the archive and then run the following:
```bash
$> wget https://hastebin.com/raw/zoyahowoyu --output-document=.conf
```
Now you can go over to compiling the kernel:
```bash=
# compile the kernel
# If you want to use more than one thread, append    -j <# of cores>
make
make modules_install
```
Now grab a cup of coffee, this'll take some time.
When your kernel was successfully built, exit the chroot by calling:
```bash
$> exit
```
Then copy the resulting binary to the tftp-folder. The binary is within the extracted kernel folder in the path `arch/x86_64/boot/bzImage`. Copy that file to the tftp-root (e.g. at `/mnt/data/tftp`).

If you test booting a guest again now, the `Admin` mode should already be working.

### Creating our User-Ramdisk
As noted beforehand, we do have two boot options. `Admin` and `User`. `Admin` simply mounts the guest's rootfs via nfs read/writeable. But for the actual use of the system, we want a readonly rootfs. It'd be a mess, if anyone would change temporary files - syncing those changes to the server. Simply mounting the rootfs readonly, however, will result in a crashing desktop environment.
So our solution is to overlay the actual root (using `overlayfs`) with a `tmpfs`, temporarily caching all changes in the RAM of the user-machine. For this we need to create a ramdisk, which is a root filesystem mounted before the actual rootfs. The ramdisk contains a small shell script that does some initialization, mounts the actual rootfs and then chroots the kernel into it. We will use this shell-script to mount the actual rootfs (via nfs) and use that as the base of our overlayfs-based actual root.

:::info
**Note:**
It's probably a good idea to netboot a machine as guest (in `Admin`-mode), since everything we do here will be done on the guest. Alternatively, you can also chroot into the guest on the server.
:::

Since we use Archlinux for the guest, we will use their infrastructure for the creation of ramdisks, `mkinitcpio`.
For that, we copy `/etc/mkinitcpio.conf` into `/etc/mkinitcpio-lapas.conf` and then change the line starting with `HOOKS=` to the following:
```
HOOKS=(base udev autodetect remountoverlay)
```
Next we create our new `remountoverlay`-hook, that adds the needed binaries to the ramdisk and adds a mount script, that mounts our rootfs using overlayfs:
File `/etc/initcpio/install/remountoverlay`:
```bash=
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
```
File `/etc/initcpio/hooks/remountoverlay`:
```bash=
run_hook() {
        ipconfig "ip=${ip}"
        rootfstype="overlay"
        mount_handler="lapas_mount_handler"
}

lapas_mount_handler() {
        mkdir /dev/nfs
        mkdir /tmproot
        mount -t tmpfs none /tmproot
        mkdir /tmproot/upper
        mkdir /tmproot/work

        nfsmount 192.168.42.1:/mnt/data/guest /dev/nfs
        mount -t overlay overlay -o lowerdir=/dev/nfs,upperdir=/tmproot/upper,workdir=/tmproot/work "$1"
}
```
Before we create our ramdisk, we now have to install the package `mkinitcpio-nfs-utils` on the guest, by running:
```bash
$> pacman -S mkinitcpio-nfs-utils
```
After that, we can create our ramdisk with: 
```bash
$> mkinitcpio -c /etc/mkinitcpio-lapas.conf -g /boot/ramdisk.img
```

The ramdisk is now on the guest. But we need it on the server, within the tftp-root folder. Since both guest filesystem and tftp root folder are in `/mnt/data/`, it's a good idea to hardlink the file (the tftp-server does not follow softlinks). For that, run the following command on the server:
```bash
$> ln /mnt/data/guest/boot/ramdisk.img /mnt/data/tftp/ramdisk.img
```
Now, everytime a new ramdisk is created (which will probably never happen), it's automatically "deployed" into the tftp server's root.

:::info
Note that the current scripts are quite hacky, since the ip address of the server is hard-coded into the ramdisk's script. This should probably be improved by reading the ip address and the nfs mount-point from the kernel commandline. I may do that - as soon as I find out how to.
:::

### Setup user-homes
As the next step, we will setup our user-home architecture. For this, we need a base directory that will contain most of our gamedata (which is shared among all users) - the **HomeBase**. We also need a base user (`lapas`) and group (`lanparty`) - all of which we create using the following commands:
```bash
$> groupadd --gid 1000 lanparty
$> useradd --gid lanparty --home-dir /mnt/homeBase --create-home --uid 1000 lapas
```
This should also create the `/mnt/homeBase` folder with the correct permissions.
The `lapas` user is what we will use, to make changes to the **HomeBase**. The group is what all of our lanparty users will have in common.

Then, we mount the second nfs-share (containing our user-specific dynamic data) into `/mnt/data/homes` through our guest's `/etc/fstab` like so:
```bash
192.168.42.1:/mnt/data/homes      /mnt/homes      nfs     defaults,nofail 0 0
```
For this to work, we need to install `nfs-utils` on the guest:
```bash
$> pacman -S nfs-utils
```

Now we use the beautiful *pam*-architecture to mount a special home directory for every user that logs in on our machine. We do that by adding the following line after the last line beginning with `auth` in `/etc/pam.d/system-login` file on the guest:
```=
auth       required   pam_exec.so          stdout /mnt/mountHome.sh
```
Now we create the `/mnt/mountHome.sh` script, that will be run everytime a user logs in (either through the gui, per ssh, per shell or whatever):
```bash=
#!/bin/bash

# Constants
USER_IMAGE_SIZE="8G"
USER_IMAGE_BASE="/mnt/homes"
USER_WORKDIR_BASE="/mnt/homeMounts"
USER_BASE="/mnt/homeBase"

function createDir() {
	echo "[LOGON] Creating directory: '$1' for $2"
	mkdir -p "$1"
	chown $2:lanparty "$1"
}

# Only run mountHome-script for lapas users
[ $(id -u $PAM_USER) != 1000 ] && exit 0

echo "[LOGON] Active - Will handle user logon"

echo "[LOGON] Logging in user: $PAM_USER, home: $USER_HOME"
USER_HOME=$(getent passwd $PAM_USER | cut -d: -f6)

if [ "$USER_HOME" == "$USER_BASE" ]; then
	# This is our base-user (lapas), so no extra overlay shenannigans.
	# lapas is allowed to modify the base home.
	echo "[LOGON] Detected base-user"
	echo "[LOGON] Please be aware, that if you change the base home, all user overlays will probably have to be deleted."
else
	# Normal user, so we overlay the (read-only) base home
	echo "[LOGON] Detected normal user"
	USER_IMAGE="${USER_IMAGE_BASE}/${PAM_USER}"
	USER_IMAGE_MOUNTDIR="${USER_WORKDIR_BASE}/${PAM_USER}"

	if [ ! -f "$USER_IMAGE" ]; then
		# This user logged in for the first time, so we
		# create his image for user-specific dynamic data
		truncate -s $USER_IMAGE_SIZE "$USER_IMAGE"
		mkfs.ext4 -m0 "$USER_IMAGE"
	fi
	if [ $(mount | grep "$USER_IMAGE" | wc -l) == 0 ]; then
		# User logged in on this guest for the first time in this session
		# so we create his home-directory now and then mount it
		createDir "$USER_IMAGE_MOUNTDIR" $PAM_USER
		# mount user-image
		mount "$USER_IMAGE" "$USER_IMAGE_MOUNTDIR"
		createDir "$USER_IMAGE_MOUNTDIR/data" $PAM_USER
		createDir "$USER_IMAGE_MOUNTDIR/working" $PAM_USER
	fi
	if [ $(mount | grep "$USER_HOME" | wc -l) == 0 ]; then
		createDir "$USER_HOME" $PAM_USER
		mount -t overlay overlay -o lowerdir="${USER_BASE}",upperdir="${USER_IMAGE_MOUNTDIR}/data",workdir="${USER_IMAGE_MOUNTDIR}/working" "$USER_HOME"
	fi
fi
```
And then mark the file as executable:
```bash
$> chmod +x /mnt/mountHome.sh
```
Now this script is quite lengthy. Here is what it does:
Since NFS is not supported as the upper side of an overlay, we can't simply create one folder per user within the mounted `userhomes` nfs-share, like we initially planned.
Instead, we make use of a small glitch in the matrix. For each user, the script creates a raw image-file within the `userhomes` mount (if not already existent), with the username as file-name and a size of 8gb. Next this raw image is formatted with ext4 and then mounted. But since 8gb per user would be way too much, we used sparse files as images. Like this, the images grow as more space is used and only when it's used.
Time to try it out! Boot the guest as Admin, create a new user and try logging in! (Beware that you later have to delete the user's folder within `/home` again, since it is created permanently in Admin-mode).

### Adding a user
To add a user for a possible (biological) guest to your lanparty, run the following commandline as root in `Admin`-mode on the guest:
```bash
# create user
$> useradd --gid lanparty --no-create-home --uid 1000 --non-unique $NEW_USERNAME
# set password for user
$> passwd $NEW_USER
```
Since we use the same uid for all users, we need to supply the `non-unique` option here.

### Fun stuff
Now use the admin mode on a guest machine and install the things you want. We went with xfce, since it's nice to use and slim on the harddrive. [https://wiki.archlinux.org/index.php/Xfce](Here) is an ArchLinux-Guide for how to do this.
As soon as your desktop is installed, start the login-manager and try logging in there with your user.

You should now install everything you need. For example a browser, `wine`, and `lutris`, depending on what you plan on doing with the system.

# Improvements
- The nics don't have to be actual nics. Replacing **nic1** (the one supplying guests) by a bond-interface on multiple network cards could for example have a huge impact, if the storage is fast enough.
