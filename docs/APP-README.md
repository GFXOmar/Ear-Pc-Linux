# Ear (PC) — unofficial Linux port

Fully offline Linux port of [ear (PC) 1.0.6](https://github.com/radiance-project/ear-pc)
(AGPL-3). The original ships only a Windows build; the backend (`main.pyc`) was
disassembled and reconstructed into `main.py`, and the abandoned pybluez C
extension was replaced with the pure-Python BlueZ shim in `bluetooth.py`
(native kernel RFCOMM/L2CAP sockets + a real SDP client, so the "NT LINK"
RFCOMM channel is always resolved from the earbuds, never hard-coded).

## Launch
- App menu: **Ear (PC)** (`~/.local/share/applications/ear-pc.desktop`), or
- terminal: `ear-pc` (`~/.local/bin/ear-pc`)

A Chromium app window opens on `http://localhost:17079` (all local, no
network access needed; Chart.js is bundled in `res/js/vendor/`). The window
opens full screen width and floating (Hyprland rules in
`~/.config/hypr/earpc.lua`, incl. `opaque` so the translucent black page
layers never ghost through), and uses its own Chromium profile at
`~/.local/share/ear-pc/.chromium-profile`, so closing the app never touches
your normal browser session. GPU compositing is left on (animations are
smooth). Logs go to stderr; run `EARPC_VERBOSE=1 ear-pc` for details (frame
hex + JS console mirror).

Startup is tuned: eel's expose-scan (a pyparsing pass over every `.js/.html`,
~2.2s on this app's 1.1 MB of mostly-vendor JS) is replaced in `main.py` by a
fast regex (`_FastExposeParser`) that finds the same names in ~10 ms — app
window visible in under 2 s. If you add JS/HTML, keep expose calls in the
plain `eel.expose(name)` form.

## Usage
1. Open your buds' case so they're awake and discoverable.
2. Click **Search** in the device list — buds (MAC prefix `2C:BE`) are scanned,
   their model ID is sniffed over the `RFCOMM COM` service and stored in
   `devicesndpreferences.db`.
3. Click a device to connect — it talks to the `NTAPP` control service and
   streams battery/ANC/EQ/gesture state from the buds.

## Notes / limitations
- Tested with **CMF Buds 2** (`2C:BE:EE:29:00:1A`, model `19ef24` / base `B179`)
  — now its primary target. See "CMF Buds 2 support" below.
- The buds must be out of the case and not asleep, else L2CAP/RFCOMM returns
  `EHOSTDOWN` until they wake.
- Tidy tray window / window dragging are Electron-only in the original and
  are stubbed out by `res/js/desktop_shim.js` in Chrome app mode.

## CMF Buds 2 support
ear-pc 1.0.6 predates the CMF line, so its UI cannot drive them properly.
The CMF Buds 2 control page from the successor project
[ear-web](https://github.com/radiance-project/ear-web) is therefore ported
into this app and selected for model `19ef24`:

- `res/MainControl/MainControl_girafarig.html` — the purpose-built page
  (correct EQ presets: Dirac OPTEO / POP / Rock / Classical / Electronic /
  Enhance vocals / Custom; noise control; ultra bass; gestures; dual
  connection; product images `res/assets/b179_black_*.webp`).
- `res/web/` — the unmodified ear-web frontend for that page
  (`bluetooth_socket.js` builds/parse the NT LINK frames in JS and fetches
  `res/js/ear_config_file.json` for per-firmware feature gating; fonts and
  `tailwind.css` are bundle-local so everything works offline).
- `res/web/web_serial_shim.js` — ear-web talks to buds through the browser's
  Web Serial API; this shim emulates `navigator.serial` over the eel bridge:
  `port.writable` → `eel.sendRaw()` → the backend RFCOMM socket, and the
  backend receive thread pushes every frame (including the unsolicited
  `55 20` status pushes fired when the state is changed from the phone app)
  → `eel.pushFrame()` → `port.readable`. Frame reassembly is CRC-checked.
- Backend (`main.py`): model `19ef24` connects the same NTAPP RFCOMM service,
  but runs a raw-mode receive thread (`receiveDataRaw`) that forwards frames
  verbatim to the page instead of using the original `operationList`
  dispatcher (`sendRaw` / `serialStatus` are exposed to JS).
- Debug-only additions: `res/web/web_debug_hook.js` mirrors the page console
  and uncaught errors into the backend log, and `sendRaw`/`receiveDataRaw`
  log each frame when `EARPC_VERBOSE=1`.
- ear(1)/Ear(stick)/Ear(2) models keep the original ear-pc pages untouched;
  their pages call the original backend readout path.
