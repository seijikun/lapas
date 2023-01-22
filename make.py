#!/bin/python3
import os;
import subprocess;

# CONFIG
MAIN_SCRIPT="src/lapas.sh";


# Preprocess the given file to a string with its contents
########################################
def preprocess(filePath, importSet = set([])):
	if(filePath in importSet):
		return bytearray();
	importSet.add(filePath);
	currentDir = os.path.dirname(filePath);
	
	scriptFile = open(filePath, "r");
	resultFileContents = bytearray();
	fileContentAsLines = scriptFile.readlines();
	for line in fileContentAsLines:
		if(line.startswith('#!import ')):
			importFilePath = line.strip('#!import ').strip();
			if(not os.path.isabs(importFilePath)):
				importFilePath = os.path.abspath(os.path.join(currentDir, importFilePath));
			if(not os.path.isfile(importFilePath)):
				raise ValueError('Import of file "{}" in from file "{}" failed, since it doesn\'t exist.'.format(importFilePath, filePath));
			resultFileContents.extend(preprocess(importFilePath, importSet));
			resultFileContents.extend("\n".encode('utf-8'));
		elif(line.startswith('#!binaryPayloadFrom ')):
			binaryPayloadCmd = line.strip('#!binaryPayloadFrom ').strip();
			binaryPayload = subprocess.check_output(binaryPayloadCmd, cwd=currentDir, shell=True);
			resultFileContents.extend(binaryPayload);
			resultFileContents.extend("\n".encode('utf-8'));
		else:
			resultFileContents.extend(line.encode('utf-8'));
	
	return resultFileContents;


os.chdir(os.path.dirname(os.path.abspath(__file__)));

mainScriptPath = os.path.abspath(MAIN_SCRIPT);
lapasScriptContents = preprocess(mainScriptPath);
resultFile = open("lapas.sh", "wb");
resultFile.write(lapasScriptContents);
resultFile.close();
