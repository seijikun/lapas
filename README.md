LAPAS
====
![Logo](docs/media/installerHeader.png)

**La**n**Pa**rty**S**erver, or LAPAS for short, is a Linux distribution configuration that simplifies the setup required to get a LAN-Party up and running.

Its architecture employs a central server that hosts a network-bootable guest operating system containing all of the software (games) required for the LAN-party. Biologicial guests connect their PCs to the internal network that LAPAS creates, activate network boot, and boot into the distribution. Then, they log in with their own user and are ready to go.

Each users settings and game states are stored in their own persistent home storage.

### Architecture
Here is a small overview of LAPAS' architecture
#### Network Architecture
The following graph shows the network architecture of LAPAS.
The internal network (connection between LAPAS and switch that connects all guests) can easily be done via an arbitrary amount of NICs in a bond setup, in order to achieve higher total bandwidths.
Since the entire guest operating system, as well as all of the game data is stored on the server, this can reduce game loading times if multiple players are connected.
```mermaid
graph BT
    lapas(LAPAS);
    subgraph "Upstream Network"
        router(Router); internet(Internet);
    end
    subgraph "Internal Network"
        switch(Switch); guest0(Guest 0); guest1(Guest 1); guestN(...);
    end

    lapas -->|DHCP\nClient| router;
    router --> internet;

    lapas ==>|DHCP\nServer| switch;
    switch --> guest0;
    switch --> guest1;
    switch --> guestN;
```

#### Services Architecture
This graph gives a light overview of all the services that make up the LAPAS functionality, as well as their connections.
```mermaid
graph LR
    lapas(LAPAS);
    lapas --> dhcpServer(DHCP-Server);
    lapas --> tftpServer(TFTP-Server);
    lapas --> nfsServer(NFS-Server);
    lapas --> ntpServer(NTP-Server);
    lapas --> dnsServer(DNS-Server);
    
    dhcpServer -.->|links to| tftpServer;
    dhcpServer -.->|links to| ntpServer;
    dhcpServer -.->|links to| dnsServer;

    tftpServer -.->|provides| Kernel-Image;
    tftpServer -.->|provides| Ramdisk;

    nfsServer -->|provides| guestRoot[Guest\nRootfilesystem];
    guestRoot -->|contains| keepEngine(Keep Engine);
    guestRoot -->|contains| baseHome[Base\nHomefolder];
    nfsServer -->|provides| userdataStorage[Userdata Storage];

    keepEngine -->|cleans up| baseHome;
    keepEngine -->|cleans up| userdataStorage;
```

#### Guest OS Architecture
The Guest OS's filesystem architecture differs between User-Mode and Admin-Mode.
The following graph shows the whole filesystem architecture in Admin-Mode:
```mermaid
graph BT
    classDef ext4Img fill:#aa3333;
    classDef mountPoint fill:#337733;
    classDef nfsShare fill:#333377;

    nfsServer(NFS-Server);
    nfsServer -.-> homes:::nfsShare;
    nfsServer -.-> guest:::nfsShare;
    subgraph "Guest OS Filesystem [Admin-Mode]"
        guest; homes;
        guest --> guestLapas["/lapas"];
        guest --> guestLib["/lib"];
        guest --> guestEtc[...];
        guest --> guestMnt["/mnt"];
        guest --> guestHome["/home"];

        guestMnt --> guestMntHomes["/homes"]:::mountPoint;
        guestMnt --> guestMntHomeBase["/homeBase"];
        guestMnt --> guestMntOverlays["/.overlays"];

        homes -..->|mounted to| guestMntHomes;
        guestMntHomes --> playerX:::ext4Img;
        
        guestMntOverlays ---> guestMntOverlaysPlayerX[playerX]:::mountPoint;
        guestMntOverlaysPlayerX --> userHomeUpper["/upper"];
        guestMntOverlaysPlayerX --> userStorageWork["/work"];

        guestHome ------> guestHomePlayerX[playerX]:::mountPoint;

        playerX -.->|mounted to| guestMntOverlaysPlayerX;
        userHomeUpper -->|overlayfs\nupper dir| guestHomePlayerX;
        userStorageWork -->|overlayfs\nwork dir| guestHomePlayerX;
        guestMntHomeBase ----->|overlayfs\nlower dir| guestHomePlayerX;
    end

    subgraph "Legend"
        nfsShare[NFS-Share]:::nfsShare;
        ext4Img[Ext4 formatted\nUserdata image]:::ext4Img;
        mountPoint[Mountpoint]:::mountPoint;
        normalDir[Directory];
    end
```

In User-Mode, the guests' root filesystem from the server is mounted readonly, so normal users can't make any permanent changes to the guest OS.
If 10 players would be logged into the same system with write access to the same network share, hell would break loose.
Though since getting a system with a pure read-only root filesystem going is hard, a tmpfs is layered on top of the guest rootfilesystem mounted from the server.
So every player can make local changes to the entire system that are stored in the RAM of their machines.
The general architecture of the guest filesystem between Admin and User-Mode is the same, the only thing that's different is how the root filesystem is handled.
This graph shows how User-Mode differs from Admin-Mode, with the identical parts left out:
```mermaid
graph BT
    classDef ext4Img fill:#aa3333;
    classDef mountPoint fill:#337733;
    classDef nfsShare fill:#333377;

    nfsServer(NFS-Server);
    nfsServer -.-> homes:::nfsShare;
    nfsServer -.-> guest:::nfsShare;
    subgraph "Guest OS Filesystem [User-Mode]"
        guest; homes;

        guestRoot["/"];
        guestRootTmpfs(tmpfs);
        guestRootTmpfs --> guestRootTmpsUpper["/upper"];
        guestRootTmpfs --> guestRootTmpsWork["/work"];
        guestRootTmpsUpper -.->|overlay\upper dir| guestRoot;
        guestRootTmpsWork -.->|overlay\nwork dir| guestRoot;

        guest -.->|overlay\nlower dir| guestRoot;
        guestRoot --> guestLapas["/lapas"];
        guestRoot --> guestLib["/lib"];
        guestRoot --> guestEtc[...];
        guestRoot --> guestMnt["/mnt"];
        guestRoot --> guestHome["/home"];
    end
```


### Requirements
- Your server needs at least 2 network cards.
	- One NIC is upstream into a network with internet (required for updates and initial installation, not necessarily required during offline lanpartys)
	- The remaining NICs form an internal network to which all the clients are connected. The script supports multiple nics by creating a bond, so you can select as many nics as you want for more bandwidth.
- Clients that support network booting / PXE booting

### Installation
This repository contains the source code for an half-interactive installer script that sets up a minimal LAPAS installation based on top of a cleanly installed Debian 11.
I suggest installing LAPAS baremetal on a host that's meant for just this purpose.
To do that, follow this process:

#### Step by Step:
- Install clean Debian 11
- Prepare the installation folder (e.g. `/mnt/lapas`)
	- Should have high I/O throughput and a large capacity. That's where all the data will be stored.
- Download the latest `lapas_installer.sh` from the GitHub Releases page onto the host
- Execute the script
