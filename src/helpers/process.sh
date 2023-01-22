function runSilentUnfallible() {
	logInfo "Running: $@";
	cmdOutput=$($@ 2>&1 >/dev/null);
	resultCode="$?";
	if [ "$resultCode" != "0" ]; then
		logError "Command: > $@ < exited unexpectedly with error code: $resultCode";
		logError "Command-Output:";
		logError "#####################"
		logError "${cmdOutput}";
		logError "#####################"
		logError "Aborting...";
		exit 1;
	fi
}
