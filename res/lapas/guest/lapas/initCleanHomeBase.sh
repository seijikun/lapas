#!/bin/bash

USER_BASE="/mnt/homeBase";

. /lapas/common.sh || exit 1;
. /lapas/parseKeepPatterns.sh || exit 1;

echo "Applying cleanup with keep patterns to overlay (transform homeBase -> cleanHomeBase)";
assertSuccessfull pushd "${USER_BASE}";
	assertSuccessfull find . \( "${FIND_KEEP_PATTERN_ARGS[@]}" \) -delete;
assertSuccessfull popd;
