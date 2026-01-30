import re
import subprocess
from collections import namedtuple
import os

# Note: On Wayland, restore() is a no-op since it's an unstandardized mess.
# The remaining (read-only) xrandr commands work though, due to xwayland

Monitor = namedtuple("Monitor", ["width", "height", "primary"])

# save current display setup (only on X11)
if os.environ.get("XDG_SESSION_TYPE") == "x11":
    subprocess.run(
        ["autorandr", "--save", "tmp", "--force"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True
    )

def restore():
    """Restore display resolution to the configuration it had before starting the shortcut"""
    if os.environ.get("XDG_SESSION_TYPE") == "x11":
        subprocess.run(
            ["autorandr", "--load", "tmp"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

def getAll():
    """Get resolutions for all monitors"""
    result = subprocess.run(
        ["xrandr", "--listactivemonitors"],
        capture_output=True,
        text=True,
        check=True
    )

    output = result.stdout.strip().splitlines()
    monitors = []

    # Skip the first line and parse the rest
    for line in output[1:]:
        match = re.search(r"\s[\+\*]?(\S+)\s+(\d+)/\d+x(\d+)/\d+\+\d+\+\d+", line)
        if match:
            is_primary = "*" in line
            width = int(match.group(2))
            height = int(match.group(3))
            monitors.append(Monitor(width=width, height=height, primary=is_primary))

    if len(monitors) == 1:
        monitors[0] = monitors[0]._replace(primary=True)

    return monitors

def getPrimary():
    """Fetch resolution of primary monitor."""
    for monitor in getAll():
        if monitor.primary:
            return monitor
    return None
