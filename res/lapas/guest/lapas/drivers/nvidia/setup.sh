#!/bin/bash

DRIVER_FOLDER=$(dirname "$0");
KERNEL_VERSION=$(uname -r);
DRIVER_RUN=$(find "$DRIVER_FOLDER" -name "NVIDIA-Linux-x86_64-*.run" | tail -n1);

if [ ! -f "$DRIVER_RUN" ]; then
        echo "Failed to find nvidia driver! Driver has to be placed alongside this script!";
        exit 1;
fi

sh "$DRIVER_RUN" --ui=none --kernel-name="$KERNEL_VERSION" --kernel-source-path="/usr/src/linux-${KERNEL_VERSION}/" --no-dkms --no-backup --no-questions --no-recursion || exit $?;