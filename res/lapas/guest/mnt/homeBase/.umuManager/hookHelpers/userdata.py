import os;
import string;
import shutil;
from enum import Enum


def applyTemplate(srcPath, dstPath, argMap):
	with open(srcPath, 'r') as file:
		tplData = file.read();
		data = string.Template(tplData).substitute(argMap);
		# make sure dstpath exists
		dstFolderPath = os.path.dirname(dstPath);
		os.makedirs(dstFolderPath, exist_ok = True);
		with open(dstPath, 'w') as file:
			file.write(data);


class SymlinkStrategy(Enum):
	"""
	Move: Move the existing source to the given destination path, then symlink back
	Empty: Start empty (empty file, empty folder), depending on what the src points to
		If src is a file, create an empty file at the given destination path, delete original src, symlink back.
		If src is a folder, create an empty folder at the given destination path, delete original src, symlink back
	"""
	Move = "Move"
	Empty = "Empty"

def setupSymlink(ctxArgs, srcPath, relDstPath, strategy = SymlinkStrategy.Move):
	"""
	This sets up a symlink relationship between a srcPath (somewhere in the wineprefix)
	and the dstPath (to store the actual data in the userdata folder).
	If dstPath already exists, this is a No-Op.
	Arguments:
	- ctxArgs is the entire arguments context of a umgrHook.
	- srcPath: Path inside the wineprefix whose user-specific content should symlinked out for storage
	- relDstPath: Destination path (relative to the userdata folder) where the data should be symlinked to.
	- strategy: Setup strategy to use
	"""
	dstPath = os.path.join(ctxArgs.USERDATA_PATH, relDstPath);

	if not os.path.exists(srcPath):
		raise FileNotFoundError("Source path does not exist");
	# initial setup already done - nothing to do
	if os.path.islink(srcPath):
		return;

	# Ensure parent directory exists
	os.makedirs(os.path.dirname(dstPath), exist_ok=True);

	if strategy is SymlinkStrategy.Move:
		# Move the source (either file or folder) to the destination, then create the symlink back.
		shutil.move(srcPath, dstPath);
		os.symlink(dstPath, srcPath);
	if strategy is SymlinkStrategy.Empty:
		# Create new empty file/folder in destination, delete original, then create the symlink back
		if os.path.isdir(srcPath):
			# Create an empty directory at destination and delete original
			os.makedirs(dstPath, exist_ok=True);
			shutil.rmtree(srcPath);
		else:
			# Create an empty file at destination and delete original
			open(dstPath, "a").close();
			os.remove(srcPath);
		os.symlink(dstPath, srcPath);
