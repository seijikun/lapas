import os;
import string;
import shutil;

def applyTemplate(srcPath, dstPath, argMap):
	with open(srcPath, 'r') as file:
		tplData = file.read();
		data = string.Template(tplData).substitute(argMap);
		# make sure dstpath exists
		dstFolderPath = os.path.dirname(dstPath);
		os.makedirs(dstFolderPath, exist_ok = True);
		with open(dstPath, 'w') as file:
			file.write(data);

def newEmptyLink(srcPath, dstPath):
	"""Given a path to either a file or folder existing within the game's installation directory, this creates a new empty file or folder
		(depending on what the original was) in the userdata folder, deletes the original and creates a link to the newly created file/folder
		to where the original was.
		Usage: helperUserdataNewEmptyLink <inputFileOrFolder> <relativeUserDataPath>
		- srcPath path to the file or folder that should be replaced by a empty file/folder linked to userdata
		- dstPath path where the file/folder should be linked from"""
	username = os.environ['USER'];
	
	if os.path.islink(srcPath):
		return; # we are done
	    
	# Ensure the userdata directory exists
	os.makedirs(user_data_path, exist_ok=True);
        
	# Check if it's a file or directory and handle accordingly
	if os.path.isfile(srcPath):
		# Create an empty file in the userdata directory
		open(dstPath, 'w').close();
		# Remove the original file
		os.remove(srcPath);
	else:
		# Create an empty folder in the userdata directory
		os.makedirs(dstPath, exist_ok=True);
		# Remove the original folder
		shutil.rmtree(srcPath);
		
	relDstPath = os.path.relpath(dstPath, srcPath);
	print(relDstPath);
	raise Exception("LOL");
	os.symlink(relDstPath, srcPath);
