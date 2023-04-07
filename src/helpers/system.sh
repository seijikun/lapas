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
