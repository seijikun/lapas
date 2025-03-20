import atexit;
import subprocess;

class ZenityProcess:
	def __init__(self, args):
		self.process = subprocess.Popen(['zenity', *args], stdin = subprocess.PIPE, text = True);
		atexit.register(self.close);
	def __enter__(self):
		return self;
	def __exit__(self, exc_type, exc_val, exc_tb):
		self.close();

	def close(self):
		if self.process != None:
			self.process.terminate();
			self.process = None;

	def setProgress(self, progress):
		self.process.stdin.write(f'{float(progress)}\n');
		self.process.stdin.flush();

	def generalArgs(title = None, windowIcon = None, width = None, height = None, timeout = None):
		args = [];
		argMap = {'title': title, 'window-icon': windowIcon, 'width': width, 'height': height, 'timeout': timeout};
		for optKey in argMap:
			optVal = argMap[optKey];
			if optVal != None:
				args.extend([f'--{optKey}', str(optVal)]);
		return args;

# API
###############################

def info(text, nowrap = False, title = None, windowIcon = None, width = None, height = None, timeout = None):
	generalArgs = ZenityProcess.generalArgs(title, windowIcon, width, height, timeout);
	args = ['--info', '--text', text, *generalArgs];
	if nowrap:
		args.append('--no-wrap');
	return ZenityProcess(args);

def progress(text, percentage = None, pulsate = False, cancelButton = True, title = None, windowIcon = None, width = None, height = None, timeout = None):
	generalArgs = ZenityProcess.generalArgs(title, windowIcon, width, height, timeout);
	args = ['--progress', '--text', text, *generalArgs];
	if percentage != None:
		args.extend(['--percentage', str(percentage)]);
	if pulsate:
		args.extend(['--pulsate']);
	if not cancelButton:
		args.extend(['--no-cancel']);
	return ZenityProcess(args);
