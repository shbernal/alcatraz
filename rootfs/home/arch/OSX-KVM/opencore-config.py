#!/usr/bin/env python3
# Prints OSX-KVM's OpenCore config with the serials from the environment, if
# set, and with the picker off if NOPICKER=true. Used for the nopicker bootdisk
# and by GENERATE_UNIQUE and GENERATE_SPECIFIC unless MASTER_PLIST_URL is set.
import os, plistlib, re, sys
with open("/home/arch/OSX-KVM/OpenCore/config.plist", "rb") as f:
    config = plistlib.load(f)
if os.environ.get("SERIAL"):
    generic = config["PlatformInfo"]["Generic"]
    generic["SystemProductName"] = os.environ["DEVICE_MODEL"]
    generic["SystemSerialNumber"] = os.environ["SERIAL"]
    generic["MLB"] = os.environ["BOARD_SERIAL"]
    generic["SystemUUID"] = os.environ["UUID"]
    generic["ROM"] = bytes.fromhex(os.environ["MAC_ADDRESS"].replace(":", ""))
    width, height = os.environ.get("WIDTH") or "1920", os.environ.get("HEIGHT") or "1080"
    config["UEFI"]["Output"]["Resolution"] = f"{width}x{height}@32"
if os.environ.get("NOPICKER") == "true":
    config["Misc"]["Boot"]["ShowPicker"] = False
    config["Misc"]["Boot"]["Timeout"] = 0
    # only list APFS and HFS volumes: with every volume, the bootdisk's own EFI
    # partition comes first, fails to boot, and OpenCore shows the picker anyway
    config["Misc"]["Security"]["ScanPolicy"] = 0x1 | 0x100 | 0x200
# the config names a kext that ships as MCEReporterDisabler.kext; without it
# AppleIntelMCEReporter panics on iMacPro1,1 and MacPro models
for kext in config["Kernel"]["Add"]:
    if kext["BundlePath"] == "AppleMCEReporterDisabler.kext" and not os.path.exists("/home/arch/OSX-KVM/OpenCore/EFI/OC/Kexts/AppleMCEReporterDisabler.kext"):
        kext["BundlePath"] = "MCEReporterDisabler.kext"
# keep <data> on one line like the original, plistlib wraps it
out = plistlib.dumps(config, sort_keys=False)
out = re.sub(rb"<data>(.*?)</data>", lambda m: b"<data>" + b"".join(m[1].split()) + b"</data>", out, flags=re.S)
sys.stdout.buffer.write(out)
