#!/bin/bash

USER_BASE="/mnt/homeBase";

if [ -f "$USER_BASE/.lapas/hooks/homeBaseBeforeCleanup.sh" ]; then
        sh "$USER_BASE/.lapas/hooks/homeBaseBeforeCleanup.sh" || exit $?;
fi

# When starting in user mode, this runs the cleanup process as specified by the homeBase/.keep file.
# All users (lapas, as well as players) thus will then have a cleaned homeBase as base for their homeFolder.
if [ -f "/.lapasUser" ]; then
        "/lapas/keepEngine" base "${USER_BASE}/.keep" "$USER_BASE" || exit $?;
fi

if [ -f "$USER_BASE/.lapas/hooks/homeBaseAfterCleanup.sh" ]; then
        sh "$USER_BASE/.lapas/hooks/homeBaseAfterCleanup.sh" || exit $?;
fi
