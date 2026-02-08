import os;
import shutil;
from typing import Protocol;
# helper dependencies
import umgr.helpers.files;

class SymlinkStrategy(Protocol):
	def check(self, linkTargetPath: str, linkPath: str): ...
	def prepare(self, linkTargetPath: str, linkPath: str, isBaseUser: bool): ...

# ------------------------------------------------------------------------

class SymlinkStrategyMove:
	"""
	User Action:
		- Move source location (file/folder) from the game to the symlink target position.
		- Create symlink from original position to target position.

	Base User Action:
		- Nothing
	"""
	def check(self, linkTargetPath: str, linkPath: str):
		if not os.path.exists(linkPath):
			raise FileNotFoundError("Source path does not exist");

	def prepare(self, linkTargetPath: str, linkPath: str, isBaseUser: bool):
		print(f"SymlinkStrategyMove::prepare({linkTargetPath}, {linkPath}, {isBaseUser})");
		if not isBaseUser:
			# Move the source (either file or folder) to the destination, then create the symlink back.
			shutil.move(linkPath, linkTargetPath);
			os.symlink(linkTargetPath, linkPath);

class SymlinkStrategyEmpty:
	"""
	User Action:
		- Clear source location (file/folder) from the game. (Replace with empty file or empty folder).
		-> SymlinkStrategyMove

	Base User Action:
		- Clear the existing source file/folder from the game. (Replace with empty file or empty folder).
	"""
	def __init__(self):
		self.inner = SymlinkStrategyMove();

	def check(self, linkTargetPath: str, linkPath: str):
		self.inner.check(linkTargetPath, linkPath);

	def prepare(self, linkTargetPath: str, linkPath: str, isBaseUser: bool):
		print(f"SymlinkStrategyEmpty::prepare({linkTargetPath}, {linkPath}, {isBaseUser})");
		# Create new empty file/folder in destination, delete original, then create the symlink back
		if os.path.isdir(linkPath):
			# Replace existing folder in source location with new empty folder
			shutil.rmtree(linkPath);
			os.makedirs(linkPath, exist_ok=False);
		else:
			# Replace existing file in source location with new empty file
			os.remove(linkPath);
			open(linkPath, "a").close();
		self.inner.prepare(linkTargetPath, linkPath, isBaseUser);


class SymlinkStrategyTplSrc:
	"""
	(File-only) strategy.

	User Action:
		- Replace source location (file) from game by applying the given template with the given args.
		-> SymlinkStrategyMove

	Base User Action:
		- Replace source location (file) from game by applying the given template with the given args.
	"""
	def __init__(self, tplPath, tplArgs):
		self.tplPath = tplPath;
		self.tplArgs = tplArgs;
		self.inner = SymlinkStrategyMove();

	def check(self, linkTargetPath: str, linkPath: str):
		return; # no checking required, we know it has to be a file

	def prepare(self, linkTargetPath: str, linkPath: str, isBaseUser: bool):
		print(f"SymlinkStrategyTplSrc::prepare({linkTargetPath}, {linkPath}, {isBaseUser})");
		if os.path.isdir(linkPath):
			raise IsADirectoryError("SymlinkStrategy TplSrc requires source to be a file");
		if os.path.exists(linkPath):
			os.remove(linkPath);
		umgr.helpers.files.applyTemplate(srcPath = self.tplPath, dstPath = linkPath, argMap = self.tplArgs);
		self.inner.prepare(linkTargetPath, linkPath, isBaseUser);


# ------------------------------------------------------------------------


def setupSymlink(ctxArgs, srcPath, relDstPath, strategy: SymlinkStrategy = SymlinkStrategyMove()):
	"""
	This sets up a symlink relationship between a srcPath (somewhere in the wineprefix)
	and the dstPath (to store the actual data in the userdata folder).
	If dstPath already exists, this is a No-Op.
	If the current user is the base-user, this is a No-Op.
	Arguments:
	- ctxArgs is the entire arguments context of a umgrHook.
	- srcPath: Path inside the wineprefix whose user-specific content should symlinked out for storage
	- relDstPath: Destination path (relative to the userdata folder) where the data should be symlinked to.
	- strategy: Setup strategy to use

	Behavior:
		This function automatically detects if it needs to do something, by checking whether the given srcPath is already a symlink.
		When the current user is the base user - this check is disabled and the strategy is executed every time.
		See Strategies for documentation about how it behaves when.

	Returns:
	- False, if nothing was done.
	- True, if the link destination did not yet exist and a link was thus created.
	"""
	username = os.environ['USER'];
	isBaseUser = (username == 'lapas');
	dstPath = os.path.join(ctxArgs.USERDATA_PATH, relDstPath);

	# Ensure parent directory exists
	if not isBaseUser:
		# initial setup already done - nothing to do
		if os.path.islink(srcPath):
			return False;
		os.makedirs(os.path.dirname(dstPath), exist_ok=True);

	# Perform strategy-specific preparation (moving, clearing or creating files)
	strategy.check(dstPath, srcPath);
	strategy.prepare(dstPath, srcPath, isBaseUser);
	return isBaseUser;
