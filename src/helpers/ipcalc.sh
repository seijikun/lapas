# From a fully qualified IP-Address (<ip>/<netmask>), get the ip address
#        192.168.42.32/24   ->   192.168.42.32
function fqIpGetIPAddress() {
	echo "${1%/*}";
}

# From a fully qualified IP-Address (<ip>/<netmask>), get the netmask in decimal notation
function fqIpGetNetmask() {
	python3 -c '
import ipaddress;
import sys;
net = ipaddress.ip_network(sys.argv[1], strict=False);
print(net.netmask);
	' "$1";
}

# From a fully qualified IP-Address (<ip>/<netmask>), get the subnet's base address
function fqIpGetSubnetAddress() {
	python3 -c '
import ipaddress;
import sys;
net = ipaddress.ip_network(sys.argv[1], strict=False);
print(net.network_address)
	' "$1";
}

# From a fully qualified IP-Address (<ip>/<netmask>), get the <n>-th usable host address in the subnet
# Usage: fqIpGetNthUsableHostaddress "<fqIp>" 10
#        192.168.42.1/24   ->   192.168.42.10
function fqIpGetNthUsableHostaddress() {
	python3 -c '
import ipaddress;
import sys;
net = ipaddress.ip_network(sys.argv[1], strict=False);
nthIp = net.network_address + int(sys.argv[2]);
print(nthIp);
	' "$1" "$2";
}

# From a fully qualified IP-Address (<ip>/<netmask>), get the subnet's last usable host address
# e.g.   192.168.42.1/24   ->   192.168.42.254
# e.g.   10.0.0.1/8        ->   10.255.255.254
function fqIpGetLastUsableHostaddress() {
	python3 -c '
import ipaddress;
import sys;
net = ipaddress.ip_network(sys.argv[1], strict=False);
lastIp = net.network_address + (net.num_addresses - 2);
print(lastIp);
	' "$1";
}
