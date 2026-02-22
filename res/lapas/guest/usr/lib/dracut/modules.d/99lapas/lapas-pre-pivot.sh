#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

if getarg ro; then
	# This is running after the overlayfs was setup.
	# We create the marker file to tell the guest system that it's running in user mode.
	echo "[lapas] Creating user mode marker file";
	touch "$NEWROOT/.lapasUser";
fi
