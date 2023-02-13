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
function getSystemDomainResolvSettings() {
	echo $(cat /etc/resolv.conf | grep -E "^domain ");
	echo $(cat /etc/resolv.conf | grep -E "^search ");
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
