# CLI asking yes/no question and validating result
# cliYesNo <prompt> <resultVarName>
function cliYesNo() {
	while true; do
		echo -n "$1 [yes/no]: ";
		read result;
		if [[ "$result" == "yes" || "$result" == "no" ]]; then
			declare -g $2="$result";
			break;
		fi
	done
}
