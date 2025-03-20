import os;
import subprocess;

# TODO: this is untested
def applyFile(protonPath, prefixPath, filePath):
	wineBinary = os.path.join(protonPath, 'files/bin/wine');
	subprocess.run(
		[wineBinary, 'regedit', filePath],
		stdout = subprocess.PIPE,
		stderr = subprocess.PIPE,
		env = { 'WINEPREFIX': prefixPath, **os.environ },
		check = True
	);
