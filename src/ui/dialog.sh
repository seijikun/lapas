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
	while true; do
		networkDeviceDialogOptions=();
		networkDeviceCnt=0;
		while read -r nicLine; do
			nicName=$(echo "$nicLine" | awk '{ print $1 }');
			nicLinkState=$(echo "$nicLine" | awk '{ print $2 }');
			nicMacAddress=$(echo "$nicLine" | awk '{ print $3 }');
			networkDeviceDialogOptions+=("${nicName}" "${nicMacAddress} [${nicLinkState}]" "off");
			networkDeviceCnt=$(($networkDeviceCnt + 1));
		done <<< $(ip -brief link show | grep --invert-match "LOOPBACK");
		
		uiDialogWithResult "tmpResult" --erase-on-exit --extra-button --extra-label "Refresh" --$listType "$2" 0 0 $networkDeviceCnt "${networkDeviceDialogOptions[@]}";
		dialogResult="$?";
		if [ "$dialogResult" == 1 ]; then exit 1; fi # Cancel
		if [ "$dialogResult" == 3 ]; then continue; fi # Refresh
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
		if [ "$?" != "0" ]; then return 1; fi
		# check validity
		(echo "${!4}" | grep -Eq "^${3}$");
		if [ "$?" == "0" ]; then
			return 0;
		else
			uiMsgbox "Input Error" "The input value was invalid. Try again.";
		fi
	done
}

# Show dialog that waits until all the given NICs have a link-state of UP
# Usage uiAwaitLinkStateUp <nic0> <nic1> ...
function uiAwaitLinkStateUp() {
	awaitingNicNames=( "$@" );
	while true; do
		linkStateDialogText=$'Awaiting link-state of active...\nPlease make sure both your internal and upstream networks are connected.\n';
		allUp=1;
		while read -r nicLine; do
			nicName=$(echo "$nicLine" | awk '{ print $1 }');
			arrayContainsElement "$nicName" "$@";
			if [ "$?" != 0 ]; then continue; fi
			nicLinkState=$(echo "$nicLine" | awk '{ print $2 }');
			nicMacAddress=$(echo "$nicLine" | awk '{ print $3 }');
			if [ "$nicLinkState" != "UP" ]; then allUp=0; fi
			
			printf -v linkStateDialogText "%s\nLink: %s [%s]: %s" "$linkStateDialogText" "$nicName" "$nicMacAddress" "$nicLinkState";
		done <<< $(ip -brief link show);
		if [ $allUp == 1 ]; then
			return 0;
		fi
		dialog --title "Awaiting NICs to come up" --infobox "${linkStateDialogText}" 0 0;
		sleep 1;
		if [ $? != 0 ]; then return 1; fi # sleep was cancelled (ctrl + c)
	done
}
