#!/bin/bash

USER_BASE="/mnt/homeBase";

"/lapas/keepEngine" base "${USER_BASE}/.keep" "$USER_BASE" || exit 1;
