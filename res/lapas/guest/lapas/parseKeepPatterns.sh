#!/bin/bash

# Patterns used to deselect files/folders that should be kept in the homeBase
export FIND_KEEP_PATTERN_ARGS=(-not -wholename "./.keep");

# Patterns used to select the files/folders that should be cleared from the user overlay
export FIND_DELETE_PATTERN_ARGS=(-wholename "./.keep"); # makes it easier with the "-or" appending

while IFS="\n" read -r patternLine; do
	patternType=$(echo "$patternLine" | awk '{print $1}');
	pattern=$(echo "$patternLine" | awk '{ st=index($0," "); print substr($0,st+1)}');

	# Append every pattern additionally with "/*" suffix, because we dont know whether its
	# a folder or a file might want to recursively keep/mask a folder and all of its contents

	# see .keep file for logic behind this
	if [ "$patternType" == "b" ]; then # delete from user overlay/workdir
		FIND_DELETE_PATTERN_ARGS+=(-or -wholename "'./$pattern'");
		FIND_DELETE_PATTERN_ARGS+=(-or -wholename "'./$pattern/*'");
	fi

	FIND_KEEP_PATTERN_ARGS+=(-and -not -wholename "'./$pattern'");
	FIND_KEEP_PATTERN_ARGS+=(-and -not -wholename "'./$pattern/*'");
done <<< $(cat "/mnt/homeBase/.keep" | grep -E "^(b |bi )");
