#!/bin/bash

# Save display configuration only if running under X11
if [ "$XDG_SESSION_TYPE" = "x11" ]; then
    autorandr --save tmp --force > /dev/null || exit 1
fi

# Restore display configuration to before the game was started
function helperResolutionRestore() {
    if [ "$XDG_SESSION_TYPE" = "x11" ]; then
        autorandr --load tmp || return 1
    fi
    return 0
}
