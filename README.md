LAPAS
====

**La**n**Pa**rty**S**erver, or LAPAS for short, is a Linux distribution configuration that simplifies the setup required to get a LAN-Party up and running.

Its architecture employs a central server that hosts a network-bootable guest operating system containing all of the software (games) required for the LAN-party. Biologicial guests connect their PCs to the internal network that LAPAS creates, activate network boot, and boot into the distribution. Then, they log in with their own user and are ready to go.

Each users settings and game states are stored in their own persistent home storage.

### Installer
![Logo](docs/media/installerHeader.png)

This repository contains the source code for an half-interactive installer script that sets up a minimal LAPAS installation based on a cleanly installed Debian 11.

#### Step by Step:
- Install clean Debian 11 on your host or a virtual machine
- Download the latest lapas.sh from the releases onto the host
- Execute the script

#### Requirements
- Your server needs at least 2 network cards.
	- One NIC is upstream into a network with internet (required for updates and initial installation, not necessarily required during offline lanpartys)
	- The remaining NICs form an internal network to which all the clients are connected. The script supports multiple nics by creating a bond, so you can select as many nics as you want for more bandwidth.
- Clients that support network booting / PXE booting
- 
