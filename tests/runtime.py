#!/usr/bin/env python3
"""Exercise gesture races, settings, and dispatch with a fake compositor CLI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time

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
    # The released gesture and Space in click mode, each exactly once.
    assert len(calls) == 2 and all(call[0] == "eval" for call in calls), calls
    for call in calls:
        lua = subprocess.run(["lua", "-", call[1]], input="hl={exec_cmd=function(c) io.write(c) end}; assert(load(arg[1]))()",
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
  binds) printf 'bind\n\tmodmask: 64\n\tkey: W\n\tdescription: Close window\n'
         lua -e "assert(loadfile('$f'))" 2>/dev/null && grep -q 'hotkey-wheel/bindings.lua' "$f" \
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
    assert helper("state").stdout.startswith("setup\n"), helper("state")
    # The same line reached through a link (a linked folder or file, as stow
    # makes) still counts, so switching the wheel off can be undone.
    elsewhere = base / "dotfiles"
    (elsewhere / "mods").mkdir(parents=True)
    (hypr / "mine.lua").rename(elsewhere / "mods/mine.lua")
    (hypr / "mods").symlink_to(elsewhere / "mods", target_is_directory=True)
    assert helper("state").stdout.startswith("setup\n"), helper("state")
    (hypr / "mods").unlink()
    (hypr / "mine.lua").symlink_to(elsewhere / "mods/mine.lua")
    assert helper("state").stdout.startswith("setup\n"), helper("state")
    by_link = helper("unsetup")
    assert by_link.returncode == 1 and "mine.lua" in by_link.stderr, by_link
    # A pipe named like a Lua file (behind a link, too) is skipped, not waited on.
    # With no line to find, the search must get past pipes named like Lua files
    # (directly and behind a linked folder) instead of waiting on them.
    (hypr / "mine.lua").unlink()
    (elsewhere / "mods/mine.lua").unlink()
    (hypr / "mods").symlink_to(elsewhere / "mods", target_is_directory=True)
    os.mkfifo(elsewhere / "mods/waiting.lua")
    os.mkfifo(hypr / "waiting.lua")
    started = time.monotonic()
    piped = subprocess.run([str(root / "hotkey-wheel"), "state"], env=setup_env, capture_output=True, text=True, timeout=10)
    assert piped.stdout.startswith("not-setup\n") and time.monotonic() - started < 2, piped
    # A search cut short (here a stand-in timeout) is never taken for "no line":
    # state, Set up and removal stop and say so, and the file stays as it was.
    cut = base / "cut-bin"
    cut.mkdir()
    (cut / "timeout").write_text("#!/bin/sh\nexit 124\n")
    (cut / "timeout").chmod(0o755)
    cut_env = dict(setup_env, PATH=str(cut) + ":" + setup_env["PATH"])
    cut_short = lambda *args: subprocess.run([str(root / "hotkey-wheel"), *args], env=cut_env, capture_output=True, text=True, timeout=20)
    before = bindings.read_text()
    for command in ("state", "setup", "unsetup"):
        result = cut_short(command)
        assert result.returncode == 1 and "could not finish searching" in result.stderr, (command, result)
    assert bindings.read_text() == before
    # grep also reports broken links and unreadable files: a broken link can't
    # hold the line, so the answer stands; an unreadable Lua file might.
    (hypr / "gone.lua").symlink_to(base / "nowhere.lua")
    assert helper("state").stdout.startswith("not-setup\n"), helper("state")
    locked = hypr / "locked.lua"
    locked.write_text("-- unreadable\n")
    locked.chmod(0)
    for command in ("state", "setup", "unsetup"):
        result = helper(command)
        assert result.returncode == 1 and "could not finish searching" in result.stderr, (command, result)
    assert bindings.read_text() == before
    locked.chmod(0o644)
    # Set up's line loads the plugin only while it is there: removing the plugin
    # (Omarchy just deletes its folder) leaves a line that does nothing.
    bindings.write_text("x = 1\n")
    locked.unlink()
    (hypr / "gone.lua").unlink()
    (base / "config/omarchy/extensions/hotkey-wheel.json").write_text('{"enabled": true}')
    assert helper("setup").stdout == "setup\n", helper("setup")
    line = bindings.read_text().splitlines()[2]
    assert line.startswith("do local p = ") and "hotkey-wheel/bindings.lua" in line, line
    stub = base / "stub-plugin"
    stub.mkdir()
    (stub / "bindings.lua").write_text('io.write("loaded")\n')
    here = line.replace(str(root), str(stub))
    gone = line.replace(str(root), str(base / "removed-plugin"))
    assert subprocess.run(["lua", "-e", here], capture_output=True, text=True).stdout == "loaded"
    removed = subprocess.run(["lua", "-e", gone], capture_output=True, text=True)
    assert removed.returncode == 0 and removed.stdout == "", removed
    assert helper("unsetup").stdout == "not-setup\n" and bindings.read_text() == "x = 1\n"
    # The plain dofile block versions before 0.7.3 wrote is still removed, also
    # from the middle of the file.
    marker = "-- >>> io.github.erikrjohansson.hotkey-wheel: added by Hotkey Wheel's Set up (remove with hotkey-wheel unsetup)"
    old_block = f'{marker}\ndofile("{root}/bindings.lua")\n-- <<< io.github.erikrjohansson.hotkey-wheel\n'
    bindings.write_text("a = 1\n" + old_block + "b = 2\n")
    assert helper("state").stdout.startswith("setup\n"), helper("state")
    assert helper("unsetup").stdout == "not-setup\n" and bindings.read_text() == "a = 1\nb = 2\n", bindings.read_text()
    # The wheel's binds over whole gestures, with a stand-in for Hyprland's Lua API.
    lua_test = subprocess.run(["lua", str(root / "tests/bindings_test.lua"), str(root / "bindings.lua")],
                              capture_output=True, text=True, timeout=10)
    assert lua_test.returncode == 0 and "PASS" in lua_test.stdout, lua_test.stdout + lua_test.stderr
    # Conflicts: the wheel's own unnamed button binds (one per other button) aren't
    # reported; a user's bind on the same button is, named or not.
    listed = base / "binds.txt"
    (sandbox / "hyprctl").write_text('#!/bin/bash\n[[ $1 == binds ]] && cat "$WHEEL_TEST_BINDS"\n')
    entry = lambda mods, key, text, how="__lua": f"bind\n\tmodmask: {mods}\n\tkey: {key}\n\tdescription: {text}\n\tdispatcher: {how}\n"
    listed.write_text(entry(0, "mouse:274", "Hotkey Wheel (hold)") + entry(0, "mouse:274", "Hotkey Wheel (release)")
                      + entry(0, "mouse:275", "") + entry(0, "mouse:276", "") + entry(0, "mouse:272", "")
                      + entry(0, "mouse:276", "Paste") + entry(0, "mouse:275", "", "exec"))
    conflicts = subprocess.run([str(root / "hotkey-wheel"), "state"], env=dict(setup_env, WHEEL_TEST_BINDS=str(listed)),
                               capture_output=True, text=True).stdout
    assert conflicts.startswith("setup\n") and sorted(conflicts.splitlines()[1:]) == \
        ["conflict\tback\tanother binding", "conflict\tforward\tPaste"], conflicts
    print("PASS: directions, edge clamp, quick release, cancel, release position, settings reload, click hit-testing, keys/scroll/Space in click mode, drawer save/merge/swap/slots/names/trigger/on-off, Save it/rename, details script reads, warnings, prompt copied via stdin, picker opens on the slot's tab, setup/unsetup, wiring through links, pipes skipped, unfinished searches refused, guarded Set up line, old blocks removed, wheel binds never removed, conflicts, exactly-once dispatch")
