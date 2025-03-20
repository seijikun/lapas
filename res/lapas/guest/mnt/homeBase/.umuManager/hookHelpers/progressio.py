import os;

class ProgressReader:
	def __init__(self, wrapped, progressCallback = None):
		"""
		Proxy class to track progress while reading from a file.
		
		:param wrapped: The readable object to wrap (e.g., a file object).
		:param progress_callback: A callable that takes the current progress (0.0 to 100.0).
		"""
		self.wrapped = wrapped;
		self.totalSize = self._getTotalSize();
		self.readBytes = 0;
		self.progressCallback = progressCallback;

	def open(filePath, mode="r", progressCallback = None):
		"""
		Static method to open a file and return a ProgressReader instance.
		
		:param file_path: Path to the file to open.
		:param mode: Mode in which to open the file (default: "r").
		:param progress_callback: A callable to report progress (takes a single float argument).
		:return: A ProgressReader instance.
		"""
		wrapped = open(filePath, mode)
		return ProgressReader(wrapped, progressCallback)

	def __enter__(self):
		return self

	def __exit__(self, exc_type, exc_val, exc_tb):
		self.close()

	def _getTotalSize(self):
		"""Get the total size of the file in bytes."""
		currentPosition = self.wrapped.tell();  # Save the current position
		self.wrapped.seek(0, 2);  # Seek to the end of the file
		totalSize = self.wrapped.tell();
		self.wrapped.seek(currentPosition);  # Restore the original position
		return totalSize;

	def read(self, size=-1):
		"""
		Reads data from the file and reports progress.
		
		:param size: Number of bytes to read (-1 reads all).
		:return: Data read from the file.
		"""
		data = self.wrapped.read(size);
		self.readBytes += len(data);
		self.progressCallback(self.totalSize, self.readBytes);
		return data

	def close(self):
		"""Close the file."""
		if self.wrapped:
			self.wrapped.close()
