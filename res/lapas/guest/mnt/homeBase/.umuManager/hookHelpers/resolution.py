import re;
import subprocess;
from collections import namedtuple

Monitor = namedtuple("Monitor", ["width", "height", "primary"]);

# save current display setup
subprocess.run(["autorandr", "--save", "tmp", "--force"], stdout = subprocess.PIPE, stderr = subprocess.PIPE, check = True);

def restore():
	"""Restore display resolution to the configuration it had before starting the shortcut"""
	subprocess.run(["autorandr", "--load", "tmp"], stdout = subprocess.PIPE, stderr = subprocess.PIPE);

def getAll():
	"""Get resolutions for all monitors"""
	# Run the "xrandr --listactivemonitors" command with check=True
	result = subprocess.run(["xrandr", "--listactivemonitors"], capture_output = True, text = True, check = True)

	# Parse the command's output
	output = result.stdout.strip().splitlines()
	monitors = []

    # Skip the first line and parse the rest
	for line in output[1:]:
		# Example line: " 0: +*eDP 2256/285x1504/190+0+0  eDP"
		match = re.search(r"\s[\+\*]?(\S+)\s+(\d+)/\d+x(\d+)/\d+\+\d+\+\d+", line)
		if match:
			# Extract resolution and primary status
			is_primary = "*" in line
			width = int(match.group(2))
			height = int(match.group(3))

			# Create a Monitor namedtuple and add it to the list
			monitors.append(Monitor(width=width, height=height, primary=is_primary))

	if len(monitors) == 1:
		monitors[0] = monitors[0]._replace(primary = True);

	return monitors

def getPrimary():
    """Fetch resolution of primary monitor."""
    for monitor in getAll():
        if monitor.primary:
            return monitor
    return None  # Return None if no primary monitor is found
