#!/bin/bash

# called by dracut
install() {
    inst_binary blockdev;
    inst_binary touch;
    inst_hook pre-mount 00 "$moddir/lapas-pre-mount.sh";
    inst_hook pre-pivot 99 "$moddir/lapas-pre-pivot.sh";
}
