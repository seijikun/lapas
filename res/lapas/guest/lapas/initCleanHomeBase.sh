#!/bin/bash

USER_BASE="/mnt/homeBase";

. /lapas/parseKeepPatterns.sh || exit 1;

echo "Applying cleanup with keep patterns to overlay (transform homeBase -> cleanHomeBase)";
cd "${USER_BASE}" || exit 1;
find . \( "${FIND_KEEP_PATTERN_ARGS[@]}" \) -mount -delete 2>&1 | grep -v "Directory not empty";
exit 0;
