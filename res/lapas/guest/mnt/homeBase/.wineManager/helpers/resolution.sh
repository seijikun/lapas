#!/bin/bash

# Helper to save and restore display resolution

autorandr --save tmp --force > /dev/null || exit 1;

# Restore display configuration to before the game was started
function helperResolutionRestore() {
	autorandr --load tmp || return 1;
}
