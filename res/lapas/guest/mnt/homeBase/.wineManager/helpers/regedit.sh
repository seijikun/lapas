#!/bin/bash

# Import the given reg file
# Usage: helperRegeditApply <regFilePath>
function helperRegeditApply() {
	wine regedit "$1" || exit 1;
}
