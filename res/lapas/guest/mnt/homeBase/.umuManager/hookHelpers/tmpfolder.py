import os;

def _getPath(bottleName):
	username = os.environ['USER'];
	return f'/tmp/lapas/{username}/{bottleName}';

def _checkIsPidRunning(pid):
	""" Check For the existence of a unix pid. """
	try:
		os.kill(pid, 0);
		return True;
	except OSError:
		return False

###############################################################

def create(bottleName):
	tmpPath = _getPath(bottleName);
	os.makedirs(tmpPath, exist_ok = True);
	return tmpPath;

def lock(bottleName):
	lockFilePath = os.path.join(_getPath(bottleName), 'lock.pid');
	# test/cleanup pre-existing lock if any
	if os.path.isfile(lockFilePath):
		with open(lockFilePath, "r") as file:
			lockPid = int(file.read().strip());
			if _checkIsPidRunning(lockPid):
				raise Exception("Already locked!");
			print("[TMPFOLDER] Stale lock detected, deleting");
			os.remove(lockFilePath);
	# create lock
	with open(lockFilePath, "w") as file:
		file.write(str(os.getpid()));

def createLocked(bottleName):
	path = create(bottleName);
	lock(bottleName);
	return path;
