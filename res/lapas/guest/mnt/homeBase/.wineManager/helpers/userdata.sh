#!/bin/bash

# Helper script that contains methods for handling with misbehaving games that store their config- and savegame files
# in their installation folder. This helper provides method to move / link them out into the user-specific userdata directory.


# Move the already existing file or folder from the game installation folder into the given path in the userdata folder and
# create a link. [Run only for normal users, not the base user]
# Usage: helperUserdataMoveLink <inputFileOrFolder> <relativeUserDataPath>
# - inputFileOrFolder prefix relative path to the file or folder in the install folder that should be linked to userdata [e.g. drive_c/...]
# - relativeUserDataPath userdata relative path where the file/folder should be moved to [e.g. Saved Games]
function helperUserdataMoveLink() {
	inputFileOrFolder="${WM_BOTTLE_PREFIX}/$1";
	userDataPath="${WM_USERDATA_PATH}/$2";
	targetName=$(basename "$inputFileOrFolder");
	
	if [ "$USER" != "lapas" ]; then
		if [ -L "$inputFileOrFolder" ]; then return; fi
		
		if [ -f "$inputFileOrFolder" ] || [ -d "$inputFileOrFolder" ]; then
			mkdir -p "$userDataPath" || exit 1;
			mv "$inputFileOrFolder" "${userDataPath}/${targetName}" || exit 1;
			ln -rs "${userDataPath}/${targetName}" "$inputFileOrFolder" || exit 1;
		else
			echo "Source does not exist!"; exit 1;
		fi
	fi
}


# Given a path to either a file or folder existing within the game's installation directory, this creates a new empty file or folder
# (depending on what the original was) in the userdata folder, deletes the original and creates a link to the newly created file/folder
# to where the original was.
# Usage: helperUserdataNewEmptyLink <inputFileOrFolder> <relativeUserDataPath>
# - inputFileOrFolder prefix relative path to the file or folder that should be replaced by a empty file/folder linked to userdata
# - relativeUserDataPath userdata relative path where the file/folder should be moved to [e.g. Saved Games]
function helperUserdataNewEmptyLink() {
	inputFileOrFolder="${WM_BOTTLE_PREFIX}/$1";
	userDataPath="${WM_USERDATA_PATH}/$2";
	targetName=$(basename "$inputFileOrFolder");
	targetPath="$userDataPath/$targetName";
	
	if [ "$USER" != "lapas" ]; then
		if [ -L "$inputFileOrFolder" ]; then return; fi
		
		mkdir -p "$userDataPath" || exit 1;
		if [ -f "$inputFileOrFolder" ]; then
			touch "$targetPath" || exit 1;
			rm "$inputFileOrFolder" || exit 1;
		elif [ -d "$inputFileOrFolder" ]; then
			mkdir "$targetPath" || exit 1;
			rm -r "$inputFileOrFolder" || exit 1;
		else
			echo "Source does not exist!"; exit 1;
		fi
		ln -rs "$targetPath" "$inputFileOrFolder" || exit 1;
	fi
}
