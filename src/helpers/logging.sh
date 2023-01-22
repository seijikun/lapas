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
