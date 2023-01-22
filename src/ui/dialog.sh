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
