import os;
import string;
import tempfile;

def stringReplace(filepath, needle, replacement):
	"""
	Replace all occurrences of a string in a file, similar to:
		sed -i 's/OLD/NEW/g' file

	Parameters
	----------
	filepath : str
		Path to the file to modify.
	needle : str
		The substring to search for.
	replacement : str
		The replacement substring.
	"""
	with open(filepath, "r", encoding="utf-8") as f:
		content = f.read();
	content = content.replace(old, new);
	with open(filepath, "w", encoding="utf-8") as f:
		f.write(content);


def applyTemplate(srcPath, dstPath, argMap):
	"""
	Apply a string.Template substitution to a source file and write the
	rendered result to a destination file.

	Parameters
	----------
	srcPath : str
		Path to the template file. The file should contain placeholders
		compatible with `string.Template`, such as ``${name}`` or ``$value``.
	dstPath : str
		Path where the rendered output should be written. Parent directories
		are created automatically if they do not exist.
	argMap : dict
		A mapping of placeholder names to replacement values. Keys correspond
		to template variable names, and values are substituted as strings.

	Notes
	-----
	- This function reads the entire template file into memory.
	- Missing keys in `argMap` will raise a `KeyError` because
		`Template.substitute()` enforces strict substitution.
	"""
	with open(srcPath, 'r') as file:
		tplData = file.read();
		data = string.Template(tplData).substitute(argMap);
		# make sure dstpath exists
		dstFolderPath = os.path.dirname(dstPath);
		os.makedirs(dstFolderPath, exist_ok = True);
		with open(dstPath, 'w') as file:
			file.write(data);
