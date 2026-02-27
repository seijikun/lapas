import os;

def umgrHook_beforeShortcutStart(args):
	# On first startup, set default name to username
	username = os.environ['USER'];

	# original goldberg emulator
	goldbergSettingsDir = os.path.join(args.USERDATA_PATH, 'AppData/Roaming/Goldberg SteamEmu Saves/settings');
	os.makedirs(goldbergSettingsDir, exist_ok = True);
	goldbergAccountNameFilePath = os.path.join(goldbergSettingsDir, 'account_name.txt');
	if not os.path.isfile(goldbergAccountNameFilePath) or username == "lapas":
		print('[GOLDBERG]: Creating account_name file');
		with open(goldbergAccountNameFilePath, 'w') as file:
			file.write(username);

	# fork: https://github.com/Detanup01/gbe_fork
	gseSettingsDir = os.path.join(args.USERDATA_PATH, 'AppData/Roaming/GSE Saves/settings/');
	os.makedirs(gseSettingsDir, exist_ok = True);
	gseUserConfigFilePath = os.path.join(gseSettingsDir, 'configs.user.ini');
	if not os.path.isfile(gseUserConfigFilePath) or username == "lapas":
		print('[GOLDBERG]: Creating user config file');
		userConfig = f"""
[user::general]
account_name={username}
language=english
ip_country=US
	""";
		with open(gseUserConfigFilePath, 'w') as file:
			file.write(userConfig);


# For multiplay to work, the steam games using goldberg emulator need to have their own appid in a certain textfile.
# Otherwise players can't join each other's servers in the LAN menu.
def prepareSteamApp(appFolder: str, appId: int):
    targets = {"steam_api.dll", "steam_api64.dll"};

    for root, dirs, files in os.walk(appFolder):
        for f in files:
            if f.lower() in targets:
                dll_path = os.path.join(root, f)
                appid_path = os.path.join(root, "steam_appid.txt");

                with open(appid_path, "w", encoding="utf-8") as out:
                    out.write(str(appId));
