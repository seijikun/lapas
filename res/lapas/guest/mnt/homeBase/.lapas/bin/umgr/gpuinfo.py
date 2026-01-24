import shutil;
import subprocess;

def hasVulkanGpu():
    # Check if vulkaninfo is available in PATH
    if shutil.which("vulkaninfo") is None:
        return False

    try:
        # Run vulkaninfo and capture output
        result = subprocess.run(
            ["vulkaninfo"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        );

        if result.returncode != 0:
            return False;

        output = result.stdout.lower()

        # Basic heuristic: look for physical device info
        if "gpu id" in output or "physical device" in output:
            return True;
        else:
            return False;

    except Exception as e:
        return False;
