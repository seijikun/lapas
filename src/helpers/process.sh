function runSilentUnfallible() {
	logInfo "Running: $@";
	cmdOutput=$($@ 2>&1 >/dev/null);
	resultCode="$?";
	if [ "$resultCode" != "0" ]; then
		logError "Command: > $@ < exited unexpectedly with error code: $resultCode";
		logError "PWD: ${PWD}";
		logError "Command-Output:";
		logError "#####################"
		logError "${cmdOutput}";
		logError "#####################"
		logError "Aborting...";
		exit 1;
	fi
}

function runUnfallible() {
	logInfo "Running: $@";
	"$@";
	resultCode="$?";
	if [ "$resultCode" != "0" ]; then
		logError "Command: > $@ < exited unexpectedly with error code: $resultCode";
		logError "See log output above. Aborting...";
		exit 1;
	fi
}
