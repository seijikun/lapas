import atexit;
import shutil;
import tarfile;
import umgr.zenity;
# helper dependencies
import umgr.helpers.tmpfolder;
from umgr.helpers.progressio import ProgressReader;

def unpackTo(archivePath, targetPath):
	with umgr.zenity.progress('Unpacking files...', title = 'Preparing') as progressWindow:
		progressCallback = lambda total, current: progressWindow.setProgress((current / total) * 100);
		with ProgressReader.open(archivePath, mode = 'rb', progressCallback = progressCallback) as file:
			tar = tarfile.open(fileobj = file, mode='r|*');
			tar.extractall(path = targetPath);

def unpackToTmp(bottleName, archivePath):
	targetPath = umgr.helpers.tmpfolder.createLocked(bottleName);
	unpackTo(archivePath, targetPath);
	# delete when process closes
	atexit.register(lambda : shutil.rmtree(targetPath));
	return targetPath;
