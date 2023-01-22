# Get stream of the binary payload contained in the given <inputFile> between the first two instances of <payloadMarker>
# The last newline character between content and end marker will be removed to properly binary data
# Usage: streamBinaryPayload <inputFile> <payloadMarker>
function streamBinaryPayload() {
	inputFile="$1"; payloadMarker="$2"; destinationFile="$3";
	# determine line number where payload starts
	PAYLOAD_START_LINE=$(cat "$inputFile" | awk "/^${payloadMarker}/ { print NR + 1; exit 0; }");
	PAYLOAD_LINE_COUNT=$(cat "$inputFile" | tail -n +${PAYLOAD_START_LINE} | awk "/^${payloadMarker}/ { print NR + 1; exit 0; }");
	PAYLOAD_LINE_COUNT=$(($PAYLOAD_LINE_COUNT - 2));
	# Cut off between both payload markers. Remove the last newline char between content and end marker
	tail -n +${PAYLOAD_START_LINE} "$inputFile" | head -n ${PAYLOAD_LINE_COUNT} | head --bytes=-1 || return $?;
}
