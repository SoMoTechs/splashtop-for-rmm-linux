# Splashtop for RMM on Linux — 2026 Working Guide

**Status: confirmed working.** Live SuperOps → Splashtop remote session from Pop!_OS 24.04, August 2026.

This builds on [siddolo/splashtop-for-rmm-linux](https://github.com/siddolo/splashtop-for-rmm-linux),
which supplied the key insight — the `st-rmm://` URL handler — back in 2022. That repo is correct
and still essential, but it predates the single biggest gotcha, which will make a correct setup
fail anyway. This guide adds that piece and updates everything for current versions.

Tested on:

| | |
|---|---|
| Distro | Pop!_OS 24.04 LTS (Ubuntu 24.04 "noble" base) |
| Wine | **11.15 Staging** (from WineHQ, *not* the distro package) |
| Client | `Splashtop_RMM_Win_INSTALLER_v3.8.2.2.exe` |
| RMM | SuperOps (works identically for NinjaRMM, Atera, Syncro — same OEM viewer) |

---

## TL;DR — the two things that break it

1. **Your distro's Wine is too old.** Ubuntu/Debian/Pop ship Wine 9.0. The client calls
   `shcore.dll.RegisterScaleChangeNotifications`, which Wine shipped only as an aborting stub until
   **Wine 9.3**. You need 9.3 or newer. This is [WineHQ bug #56244](https://bugs.winehq.org/show_bug.cgi?id=56244),
   filed against this exact software.
2. **The `st-rmm://` handler doesn't register itself.** Installing the client is not enough. Without
   a handler, clicking *Remote* in your RMM does nothing at all — silently, with no error anywhere.

Fix both and it works.

---

## Quick install

If you already have Wine ≥ 9.3 and the client installed, this repo does steps 3 and 4 for you:

```bash
git clone https://github.com/SOMOREPO/splashtop-for-rmm-linux.git
cd splashtop-for-rmm-linux
./install.sh
```

It refuses to run on Wine older than 9.3 and tells you why. Otherwise follow the full walkthrough below.

---

## 1. Install Wine 11.x from WineHQ

Do **not** use `apt install wine`. Distro Wine is 9.0 and will abort.

```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -qNP /etc/apt/sources.list.d/ \
  https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
sudo apt update
sudo apt install --install-recommends winehq-staging
```

Replace `noble` with your release (`jammy`, `bookworm`, …). Verify:

```bash
wine --version    # must be >= 9.3; 11.15 confirmed working
```

> **Do not try to verify the fix by grepping the DLL.** `__wine_stub_RegisterScaleChangeNotifications`
> is *still present* as a string in Wine 11.15's `shcore.dll` even though the crash no longer happens.
> Test by running the client, not by inspecting symbols.

## 2. Install the client in a dedicated prefix

A separate prefix keeps this isolated from your other Wine apps.

```bash
export WINEPREFIX="$HOME/.wine-splashtop"
wineboot -u
```

Get the installer. The generic Splashtop RMM build works regardless of which RMM you use —
the session details all arrive in the URL payload:

```bash
wget -O SplashtopRMM.exe \
  https://download.splashtop.com/rmm/Splashtop_RMM_Win_INSTALLER_v3.8.2.2.exe
```

(Your RMM may host its own copy — e.g. NinjaRMM at `resources.ninjarmm.com/Splashtop/`. Either works.)

**Silent install works** — no clicking through a wizard:

```bash
WINEPREFIX="$HOME/.wine-splashtop" wine SplashtopRMM.exe /s
```

Confirm it landed:

```bash
ls "$HOME/.wine-splashtop/drive_c/Program Files (x86)/Splashtop/Splashtop Remote/Client for RMM/"
# clientoobe.exe  strwinclt.exe  strwinfile.exe  strwinchat.exe  ...
```

## 3. Register the `st-rmm://` handler

Your RMM's web console launches sessions by opening a `st-rmm://` URL. The handler strips the
scheme and passes the payload to `clientoobe.exe -a`.

`~/bin/splashtop-rmm-handler`:

```bash
#!/usr/bin/env bash
export WINEPREFIX="$HOME/.wine-splashtop"
export WINEDEBUG=-all
CLIENT="$WINEPREFIX/drive_c/Program Files (x86)/Splashtop/Splashtop Remote/Client for RMM/clientoobe.exe"
LOG="$WINEPREFIX/handler.log"

url="$1"
payload="${url#st-rmm://}"      # strip scheme
payload="${payload%/}"          # strip trailing slash some browsers append

{ echo "--- $(date -Is)"; echo "raw:     $url"; echo "payload: $payload"; } >> "$LOG"

if [ ! -f "$CLIENT" ]; then
  echo "ERROR: clientoobe.exe missing at $CLIENT" >> "$LOG"
  exit 1
fi

exec wine "$CLIENT" -a "$payload" >> "$LOG" 2>&1
```

The logging is not decoration — it is the only way to tell "the browser never called me" apart from
"the client failed", and those have completely different fixes.

`~/.local/share/applications/splashtop-rmm.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Splashtop for RMM
Comment=Splashtop RMM viewer (Wine) — handles st-rmm:// links
Exec=/home/YOUR_USER/bin/splashtop-rmm-handler %u
Icon=/home/YOUR_USER/.wine-splashtop/drive_c/Program Files (x86)/Splashtop/Splashtop Remote/Client for RMM/strwinclt.exe
Terminal=false
Categories=Network;RemoteAccess;
MimeType=x-scheme-handler/st-rmm;
```

`Exec` must be an absolute path — `~` and `$HOME` are not expanded in desktop files.

```bash
chmod +x ~/bin/splashtop-rmm-handler
update-desktop-database ~/.local/share/applications
xdg-mime default splashtop-rmm.desktop x-scheme-handler/st-rmm
```

## 4. Test the plumbing before touching your RMM

```bash
xdg-open "st-rmm://PLUMBING-TEST-12345"
cat ~/.wine-splashtop/handler.log
```

You want to see the payload stripped to `PLUMBING-TEST-12345`. If nothing is logged, the desktop
entry isn't registered and no amount of Wine tinkering will help.

Then click **Remote** on a machine in your RMM. A real payload looks like:

```
st-rmm://com.splashtop.remote?rmm_code=…&rmm_session_pwd=…&rmm_token=…
        &rmm_callback=https%3A%2F%2Fapi-msp.superops.ai%2F…&rmm_sessionid=…
        &computername=…&auto_reconnect=300
```

---

## Troubleshooting

**Clicking Remote does nothing, no window, no error**
Check `~/.wine-splashtop/handler.log`. Empty → the browser never fired the handler; re-run the
`xdg-mime default` step and check `~/.config/mimeapps.list` for a stale
`x-scheme-handler/st-rmm=` line pointing at a `.desktop` file that no longer exists. That stale
entry is easy to acquire from a previous attempt and it silently swallows every click.

**`unimplemented function shcore.dll.RegisterScaleChangeNotifications, aborting`**
Wine is older than 9.3. The backtrace will name your version:

```
1 __wine_spec_unimplemented_stub(module="shcore.dll",
    function="RegisterScaleChangeNotifications")  [dlls/winecrt0/stub.c:32]
...
9 WINPROC_CallDlgProcW(msg=0x110)                 ← WM_INITDIALOG
```

`msg=0x110` is `WM_INITDIALOG` — it dies building a dialog, nowhere near video. Upgrade Wine.

**A Wine log looks clean but the app definitely crashed**
Wine's debugger flushes *after* the parent process exits. Reading the log immediately gives a false
negative. Wait a few seconds, then read the file. This wasted real time during this write-up.

**Don't bother with the Splashtop Business Linux app**
A native Linux build exists (`download.splashtop.com/linuxclient/splashtop-business_Ubuntu_v3.8.2.0_amd64.tar.gz`)
but it authenticates against Business Access, not your RMM tenant, so it can't open RMM sessions.
Its `.deb` also still declares Ubuntu 22.04 dependency names (`libgcc1`, `libqt5core5a`,
`libqt5gui5`, `libqt5network5`, `libqt5widgets5`) that don't exist on 24.04 — repack with
`libgcc-s1` and the `libqt5*5t64` names if you want it for Business Access.

**There is no Linux RMM client, so stop looking**
`my.splashtop.com/rmm/mac` and `/rmm/win` redirect to real installers. `/rmm/linux`, `/rmm/ubuntu`
and `/rmm/deb` just bounce to the login page. Windows and Mac only — that's why your RMM's download
page offers nothing else.

---

## Fallback: the Splashtop Web App

If you'd rather not run Wine, `my.splashtop.com` → pick the machine → **"From the Web App in this
browser."** Browser-based, no install, works fine on Linux. The tradeoff is that it bypasses the
`st-rmm://` handoff, so you launch from Splashtop's UI rather than your RMM's asset page.

---

## Credit

The `st-rmm://` handler approach is from [siddolo/splashtop-for-rmm-linux](https://github.com/siddolo/splashtop-for-rmm-linux)
(2022, tested against NinjaRMM). This guide adds the Wine ≥ 9.3 requirement, current v3.8.2.2
silent-install steps, SuperOps verification, and the troubleshooting notes above.

Verified against a live SuperOps session by **Tony Gormley — [Somo Technologies LLC](https://somotechs.com)**, August 2026.
