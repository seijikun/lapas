#!/bin/bash
if [ ! "$BASH_VERSION" ]; then exec /bin/bash "$0" "$@"; fi
export USER="root";

# import LAPAS config
. $(dirname "$0")/config;

function handleClient() {
        1>&2 echo "Awaiting authentication...";
        read authPassword || return 1;
        authPasswordHash=$(echo "${LAPAS_PASSWORD_SALT}${authPassword}" | sha512sum | cut -d" " -f1);
        if [ "$LAPAS_PASSWORD_HASH" != "$authPasswordHash" ]; then
                1>&2 echo "Authentication failed... closing connection";
                echo "1 Auth failed (wrong password)"; return 1;
        fi
        echo "0 Auth Ok";

        1>&2 echo "Authentication successful. Waiting for command...";
        read -t 5 COMMAND || return 1;
        if [ "$COMMAND" == "noop" ]; then
                1>&2 echo "Handling: noop";
                echo "0 Success"; return 0; # mostly meant for auth testing
        fi
        if [ "$COMMAND" == "addUser" ]; then
                1>&2 echo "Handling: addUser";
                read -t 5 newUsername || return 1;
                read -t 5 newPassword || return 1;
                if [ "$newPassword" == "" ]; then
                        echo "3 Command Failed (empty password not allowed)"; return 1;
                fi
                opSuccess=0;
		# try 4 times to work around weird nfs locking behavior (in certain situations, the first
		# three attempts will fail, because openat() of /etc/{passwd,group,gshadow} will return
		# EAGAIN and useradd doesn't like that.
                for attemptIdx in {1..4}; do
                        ADDUSER_LOG=$($(dirname "$0")/addUser.sh "$newUsername" "$newPassword" 2>&1);
                        if [ $? == 0 ]; then
                                opSuccess=1;
                                break;
                        fi
                        1>&2 echo "addUser (Attempt $attemptIdx / 3) failed: ${ADDUSER_LOG}";
                        sleep 1; # short sleep before we try again
                done
                if [ $opSuccess == 1 ]; then
                        1>&2 echo "Added user: ${newUsername}";
                        echo "0 Success"; return 0;
                else
                        1>&2 echo "Adding user ${newUsername} failed";
                        echo "3 Command Failed (${ADDUSER_LOG})"; return 1;
                fi
        else
                1>&2 echo "Received unknown command: ${COMMAND}";
                echo "2 Unknown command"; return 1;
        fi
};
export -f handleClient;

while true; do
        echo "Waiting for API client...";
        coproc serv { nc -q0 -lp 1337; }
        handleClient <&${serv[0]} >&${serv[1]};
        # close our outgoing stream
        exec {serv[1]}>&-;
        wait $serv_PID;
        echo "Disconnected.";
        echo "###########################";
done
