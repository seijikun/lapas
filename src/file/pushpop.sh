function pushd () {
    command pushd "$@" > /dev/null;
    return $?;
}

function popd () {
    command popd "$@" > /dev/null;
    return $?;
}



# To a given ($1) file, add a temporary override with the content piped into this function
# This will rename "$1" to "$1.backup" and replace "$1" with the content from stdin.
function pushFileOverride() {
	if [ -f "$1.backup" ]; then
		echo "No stacking for overrides supported yet";
		exit 1;
	fi
	mv "$1" "$1.backup" || return 1;
	cat - > "$1" || return 1;
}

# Pop previously generated override for file "$1"
function popFileOverride() {
	mv "$1.backup" "$1" || return 1;
}
