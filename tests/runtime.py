#!/usr/bin/env python3
"""Exercise gesture races, settings, and dispatch with a fake compositor CLI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading

root = Path(__file__).resolve().parents[1]
shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
with tempfile.TemporaryDirectory(prefix="hotkey-wheel-test-") as directory:
    base = Path(directory)
    for module in ("Commons", "Ui", "services"):
        (base / module).symlink_to(shell / module, target_is_directory=True)
    (base / "bin").mkdir()
    fake = base / "bin" / "hyprctl"
    fake.write_text('''#!/usr/bin/python3
import json, os, sys
if "cursorpos" in sys.argv:
    cursor = os.environ["WHEEL_TEST_CURSOR"]
    print(open(cursor).read() if os.path.exists(cursor) else '{"x":400,"y":400}')
elif "eval" in sys.argv:
    with open(os.environ["WHEEL_TEST_LOG"], "a") as file: file.write(json.dumps(sys.argv[1:]) + "\\n")
else: print('{}')
''')
    fake.chmod(0o755)
    # Logs what wl-copy gets on the command line and on stdin, separately.
    copier = base / "bin" / "wl-copy"
    copier.write_text('''#!/usr/bin/python3
import json, os, sys
with open(os.environ["WHEEL_TEST_LOG"] + ".copy", "a") as file:
    file.write(json.dumps({"argv": sys.argv[1:], "stdin": sys.stdin.read()}) + "\\n")
''')
    copier.chmod(0o755)
    source = (root / "tests/runtime.qml").read_text()
    source = source.replace("PLUGIN_PATH", root.as_uri()).replace("ACTIONS_PATH", (root / "Actions.js").as_uri())
    (base / "shell.qml").write_text(source)
    display = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
    if not display.startswith("/"):
        display = str(Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) / display)
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software", WAYLAND_DISPLAY=display,
               QT_QPA_PLATFORMTHEME="basic", QT_QUICK_CONTROLS_STYLE="Basic", LANGUAGE="sv:de",
               XDG_CONFIG_HOME=str(base / "config"), XDG_CACHE_HOME=str(base / "cache"),
               XDG_RUNTIME_DIR=str(base / "run"),
               PATH=str(base / "bin") + ":" + os.environ["PATH"], WHEEL_TEST_LOG=str(base / "dispatch.jsonl"),
               WHEEL_TEST_CURSOR=str(base / "cursor.json"))
    (base / "run").mkdir(mode=0o700)
    # Scripts the details window reads (paths in $HOME, which is the test dir).
    env["HOME"] = str(base)
    (base / "scripts").mkdir()
    (base / "scripts/a.sh").write_text("#!/bin/sh\necho reviewed\n")
    os.mkfifo(base / "scripts/pipe.sh")
    (base / "scripts/latin1.sh").write_bytes(b"#!/bin/sh\necho caf\xe9\n")
    # Watches every process's command line for the prompt's marker while the test runs
    # (not the processes that started this test, whose command lines may mention it).
    leaks, scanning, starters, pid = [], threading.Event(), set(), os.getppid()
    while pid > 1:
        starters.add(str(pid))
        pid = int(Path("/proc", str(pid), "stat").read_text().rsplit(")", 1)[1].split()[1])
    def scan():
        while not scanning.is_set():
            for pid in os.listdir("/proc"):
                try:
                    if pid.isdigit() and pid not in starters and b"CMD-MARKER-7" in Path("/proc", pid, "cmdline").read_bytes():
                        leaks.append(Path("/proc", pid, "cmdline").read_bytes()[:300])
                except OSError: pass
    scanner = threading.Thread(target=scan, daemon=True)
    scanner.start()
    try:
        result = subprocess.run(["qs", "-p", str(base / "shell.qml"), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=12)
    except subprocess.TimeoutExpired as error:
        raise AssertionError(str(error.stdout) + str(error.stderr)) from None
    log = result.stdout + result.stderr
    assert result.returncode == 0 and "HOTKEY_WHEEL_OK" in log, log
    assert not any(error in log for error in ("ReferenceError", "TypeError", "Error:", "is not a type", "Binding loop")), log
    calls = [json.loads(line) for line in (base / "dispatch.jsonl").read_text().splitlines()]
    assert len(calls) == 1 and calls[0][0] == "eval", calls
    lua = subprocess.run(["lua", "-", calls[0][1]], input="hl={exec_cmd=function(c) io.write(c) end}; assert(load(arg[1]))()",
                         capture_output=True, text=True, check=True)
    assert lua.stdout == "printf hotkey-wheel-test", lua.stdout
    # The agent prompt (here with the request, CMD-MARKER-7) reaches wl-copy on stdin only, without the slot's command.
    scanning.set()
    scanner.join()
    assert not leaks, "prompt text seen in a process's arguments: " + str(sorted(set(leaks)))
    copies = [json.loads(line) for line in (base / "dispatch.jsonl.copy").read_text().splitlines()]
    assert len(copies) == 1 and copies[0]["argv"] == ["--type", "text/plain"] and "CMD-MARKER-7" in copies[0]["stdin"] \
        and "SLOT-MARKER-3" not in copies[0]["stdin"], copies
    saved = json.loads((base / "config/omarchy/extensions/hotkey-wheel.json").read_text())
    library = json.loads((base / "config/omarchy/extensions/hotkey-wheel-custom.json").read_text())
    assert library == {"version": 1, "commands": [{"label": "Blurry", "icon": "", "command": "blur", "description": "Blurs it more."},
                                                  {"label": "Pad", "icon": "p", "command": "echo pad"}]}, library
    assert saved["actions"][0]["label"] == "Test action"
    # The drawer wrote the new trigger without saving its draft.
    assert saved["trigger"] == "back" and saved["actions"][0]["label"] != "Draft" and saved["labels"] is True, saved
    # ...and then switched it off, keeping the trigger.
    assert saved["enabled"] is False, saved
    # Set up and removal, against a sandboxed Hyprland that loads the config
    # with real Lua: a line Hyprland can't take is put back out of the file.
    hypr = base / "config/hypr"
    hypr.mkdir(parents=True, exist_ok=True)
    sandbox = base / "sandbox-bin"
    sandbox.mkdir()
    (sandbox / "hyprctl").write_text(r"""#!/bin/bash
f="$XDG_CONFIG_HOME/hypr/bindings.lua"
case "$1" in
  binds) lua -e "assert(loadfile('$f'))" 2>/dev/null && grep -q 'hotkey-wheel/bindings.lua' "$f" \
           && printf 'bind\n\tmodmask: 0\n\tkey: mouse:274\n\tdescription: Hotkey Wheel (hold)\n' ;;
  configerrors) lua -e "assert(loadfile('$f'))" 2>&1 >/dev/null | head -n1 ;;
esac
""")
    (sandbox / "omarchy-shell").write_text("#!/bin/sh\n:\n")
    for tool in sandbox.iterdir(): tool.chmod(0o755)
    (base / "config/omarchy/extensions/hotkey-wheel.json").write_text('{"enabled": true}')
    setup_env = dict(env, PATH=str(sandbox) + ":/usr/bin")
    helper = lambda *args: subprocess.run([str(root / "hotkey-wheel"), *args], env=setup_env, capture_output=True, text=True)
    bindings = hypr / "bindings.lua"
    bindings.write_text("x = 1\nreturn {}")
    broken = helper("setup")
    assert broken.returncode == 1 and "put back" in broken.stderr and bindings.read_text() == "x = 1\nreturn {}", broken
    bindings.write_text("x = 1\n")
    assert helper("setup").stdout == "setup\n" and "hotkey-wheel/bindings.lua" in bindings.read_text()
    assert helper("unsetup").stdout == "not-setup\n" and bindings.read_text() == "x = 1\n"
    # A line added by hand, here in another file it loads, is never left behind silently.
    (hypr / "mine.lua").write_text('dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.erikrjohansson.hotkey-wheel/bindings.lua")\n')
    (base / "config/omarchy/extensions/hotkey-wheel.json").write_text('{"enabled": false}')
    by_hand = helper("unsetup")
    assert by_hand.returncode == 1 and "mine.lua" in by_hand.stderr, by_hand
    print("PASS: directions, edge clamp, quick release, cancel, release position, settings reload, click hit-testing, drawer save/merge/swap/slots/names/trigger/on-off, Save it/rename, details script reads, warnings, prompt copied via stdin, picker opens on the slot's tab, setup/unsetup, exactly-once dispatch")
