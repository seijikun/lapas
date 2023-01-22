# Like cmake, file configure. Gets passed a list of parameters in the form "<name>=<value>" "<name>=<value>" ...
# and replaces all occurences of "@<name>@" within the stream with the corresponding <value>.
# Usage: configureStream "<name>=<value>" ...
# Example: cat <template> | configureStream "WINEPREFIX=${WINEPREFIX}" "MYVARIABLE=5"
function configureStream() {
	if [ $# != 0 ]; then
		keyVal="$1"; shift;
		varKey="${keyVal%%=*}";
		varValue="${keyVal#*=}";
		cat - | awk -v varKey="@@${varKey}@@" -v varValue="${varValue}" '
			index($0, varKey) {
				start = 1
				line = $0
				newline = ""
				while (i=index(line, varKey)) {
					newline = newline substr(line, 1, i-1) varValue
					start += i + length(varKey) - 1
					line = substr($0, start)
				}
				$0 = newline line
			}
			{print}
		' | configureStream "$@";
	else
		cat -;
	fi
}


# See configureStream
# This operates within <inputFilePath> and <outputFilePath> instead on streams. Just a small wrapper
# Hint: inputFilePath and outputFilePath may be equivalent.
# Usage: configureFile <inputFilePath> <outputFilePath> "<name>=<value>" ...
function configureFile() {
	inputFilePath="$1"; shift;
	outputFilePath="$1"; shift;
	if [ ! -f "$inputFilePath" ]; then
		1>&2 echo "configureFile: inputFile \"${inputFilePath}\" does not exist!"; exit 1;
	fi
	resultContent=$(cat "$inputFilePath" | configureStream "$@");
	echo "$resultContent" > "$outputFilePath";
	return $?;
}


# Usage configureFileInplace <inputFilePath> "<name>=<value>" ...
function configureFileInplace() {
	filePath="$1"; shift;
	configureFile "$filePath" "$filePath" "$@"; return $?;
}
