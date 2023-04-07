# Check if an array contains the given element
# Usage: arrayContainsElement <searchedElement> <arrayElements...>
# Example: arrayContainsElement "$searchedElement" "$array[@]"
# see: https://stackoverflow.com/a/8574392
function arrayContainsElement () {
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}
