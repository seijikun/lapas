#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

# root="block:/dev/..."
LAPAS_ROOTDEV=${root#block:};

if getarg ro; then
	echo "[lapas] Running user mode";
	blockdev --setro "$LAPAS_ROOTDEV";
else
	echo "[lapas] Running admin mode";
fi
