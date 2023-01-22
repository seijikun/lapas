function assertSuccessfull() {
	echo "Running: $@";
	$@;
	resultCode="$?";
	if [ "$resultCode" == 0 ]; then return 0; fi
	echo "Command: > $@ < exited unexpectedly with error code: $resultCode";
	echo "Aborting...";
	exit $resultCode;
}
export -f assertSuccessfull;
