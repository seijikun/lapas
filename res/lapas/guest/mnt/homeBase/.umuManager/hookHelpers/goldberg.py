import os;

def umgrHook_beforeShortcutStart(args):
	# On first startup, set default name to username
	goldbergSettingsDir = os.path.join(args.USERDATA_PATH, 'AppData/Roaming/Goldberg SteamEmu Saves/settings');
	os.makedirs(goldbergSettingsDir, exist_ok = True);

	goldbergAccountNameFilePath = os.path.join(goldbergSettingsDir, 'account_name.txt');
	if not os.path.isfile(goldbergAccountNameFilePath):
		print('[GOLDBERG]: Creating account_name file');
		with open(goldbergAccountNameFilePath, 'w') as file:
			file.write(os.environ['USER']);
