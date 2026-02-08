from typing import Union

LAUNCHER_TEMPLATE_DEFAULTARGS = {
	"Type": "Application",
	"Terminal": "false",
	"NoDisplay": "false",
	"Categories": "Game",
	"StartupNotify": "true",
	"PrefersNonDefaultGPU": "true,"
}

def generate(execCmd: str, args: dict[str, Union[str, list[str], None]], path: str):
	# Merge defaults with overrides
	values = { **LAUNCHER_TEMPLATE_DEFAULTARGS, **args };
	values["Exec"] = execCmd;
	# Sort keys alphabetically
	values = sorted(values.items(), key=lambda kv: len(kv[0]));

	lines = ["[Desktop Entry]"]
	for key, value in values:
		# Skip None values entirely
		if value is None:
			continue
		if isinstance(value, list):
			valueStr = ";".join(set(value));
			lines.append(f"{key}={valueStr}");
		else:
			lines.append(f"{key}={value}");

	content = "\n".join(lines) + "\n";

	with open(path, "w", encoding="utf-8") as f:
		f.write(content);
