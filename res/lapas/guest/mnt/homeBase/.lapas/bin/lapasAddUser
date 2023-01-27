#!/bin/bash
if [ ! "$BASH_VERSION" ]; then exec /bin/bash "$0" "$@"; fi

LAPAS_API_IP=$(ip route | grep "default via" | cut -d' ' -f3);
LAPAS_API_PORT=1337;

function handleNewUser() {
	while true; do
		IFS='|' CREDS=( $(zenity --forms --title "Add User" --text "Add new user" \
			--add-entry="Username" \
			--add-password="Password" \
			--add-password="Password Confirm"$) );
		if [ $? != 0 ]; then exit 0; fi
		if [ "${CREDS[0]}" == "" ]; then
			zenity --error --title="Invalid Input" --text="Username must not be empty";
			continue;
		fi
		if [ "${CREDS[1]}" == "" ]; then
			zenity --error --title="Invalid Input" --text="Password must not be empty";
			continue;
		fi
		if [ "${CREDS[1]}" != "${CREDS[2]}" ]; then
			zenity --error --title="Invalid Input" --text="Password repetition does not match password!";
			continue;
		fi
		break;
	done
	echo "addUser";
	echo "${CREDS[0]}";
	echo "${CREDS[1]}";
	read addUserResult;
	if [ "${addUserResult:0:2}" != "0 " ]; then
		zenity --error --title="Server Error" --text="Adding user failed:\n${addUserResult}";
		return 1;
	fi
}

while true; do
	# Connect to server API and authenticate
	while true; do
		lapasPassword=$(zenity --password --title="Lapas Auth");
		if [ $? != 0 ]; then exit 0; fi

		echo "Connecting to LAPAS API...";
		coproc client { nc ${LAPAS_API_IP} ${LAPAS_API_PORT}; }
		
		echo "$lapasPassword" >&${client[1]};
		read authResult <&${client[0]};
		if [ "${authResult:0:2}" == "0 " ]; then break; fi
		
		zenity --error --title="Authentication Error" --text="Authentication failed: ${authResult}";
		exec {client[1]}>&-; # close stream
		wait $client_PID;
	done

	handleNewUser <&${client[0]} >&${client[1]};
	if [ "$?" == 0 ]; then
		exec {client[1]}>&-; # close stream
		wait $client_PID;
		break;
	fi
done