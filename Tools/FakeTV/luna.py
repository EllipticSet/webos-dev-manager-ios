#!/usr/bin/python3
"""Stands in for luna-send on the fake TV."""
import json, os, shutil, sys, time

T = "/tmp/faketv"
user = os.environ.get("TV_USER", "?")
args = sys.argv[1:]
args = args[2:] if args[0] == "-n" else args[1:]
uri = args[0]
params = json.loads(args[1]) if len(args) > 1 else {}
open(T + "/luna.log", "a").write(f"{user} {uri} {json.dumps(params)}\n")
state = T + "/apps.json"
apps = json.load(open(state if os.path.exists(state) else T + "/default_apps.json"))


def out(value):
    print(json.dumps(value), flush=True)


# Homebrew Channel keeps its root settings as flag files.
FLAGS = {"telnetDisabled": "webosbrew_telnet_disabled", "failsafe": "webosbrew_failsafe",
         "sshdEnabled": "webosbrew_sshd_enabled", "blockUpdates": "webosbrew_block_updates"}


def flags():
    return {name: os.path.exists(f"{T}/var/luna/preferences/{file}") for name, file in FLAGS.items()}


if "getSystemInfo" in uri:
    out({"returnValue": True, "modelName": "OLED55FAKE", "firmwareVersion": "03.21.15",
         "sdkVersion": "6.3.0", "otaId": "HE_DTV_W22O_AFABATAA"})
elif "osInfo" in uri:
    out({"returnValue": True, "webos_release": "7.3.1", "device_name": "o22n2"})
elif "listApps" in uri:
    out({"returnValue": True, "apps": apps})
elif "applicationManager/launch" in uri:
    out({"returnValue": True, "id": params.get("id")})
elif "hbchannel.service/getConfiguration" in uri:
    out({"returnValue": True, "root": True, **flags()} if user == "root" else
        {"returnValue": False, "errorText": "Service does not exist: org.webosbrew.hbchannel.service."})
elif "hbchannel.service/setConfiguration" in uri:
    for name, value in params.items():
        if name in FLAGS:
            path = f"{T}/var/luna/preferences/{FLAGS[name]}"
            if value:
                open(path, "w").write("1")
            elif os.path.exists(path):
                os.remove(path)
    out({"returnValue": True, **{name: value for name, value in flags().items() if name in params}})
elif "hbchannel.service/reboot" in uri:
    open(T + "/reboot.log", "a").write(f"{time.ctime()}\n")
    out({"returnValue": True})
elif "hbchannel.service/install" in uri:
    for percent in (10, 50, 90):
        out({"returnValue": True, "statusText": "Installing", "progress": percent})
        time.sleep(.5)
    out({"returnValue": True, "finished": True, "statusText": "Done"})
    time.sleep(30)
elif "capture/executeOneShot" in uri:
    shutil.copy(T + "/home/apps/com.example.demo/icon.png", params["path"])
    out({"returnValue": True})
elif "dev/remove" in uri:
    json.dump([a for a in apps if a["id"] != params["id"]], open(state, "w"))
    out({"returnValue": True, "subscribed": True})
    time.sleep(.3)
    out({"returnValue": True, "details": {"state": "removed"}})
    time.sleep(30)
elif "dev/install" in uri:
    path = params["ipkUrl"]
    open(T + "/installed.log", "a").write(f"{path} {os.path.getsize(path)} {open(path, 'rb').read(8)!r}\n")
    apps.append({"id": "com.example.installed", "type": "web", "title": "Installed From IPK",
                 "vendor": "Me", "version": "0.1.0", "folderPath": T, "icon": "none.png"})
    json.dump(apps, open(state, "w"))
    out({"returnValue": True, "subscribed": True})
    time.sleep(.5)
    out({"returnValue": True, "details": {"state": "installing"}})
    time.sleep(.5)
    out({"returnValue": True, "details": {"state": "installed"}})
    time.sleep(30)
else:
    out({"returnValue": True})
