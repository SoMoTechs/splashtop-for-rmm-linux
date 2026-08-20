#!/usr/bin/env bash
# Installs the st-rmm:// handler for the Splashtop RMM client under Wine.
# Assumes Wine >= 9.3 and the client already installed. See README.md.
set -e

PREFIX="${WINEPREFIX:-$HOME/.wine-splashtop}"
CLIENT="$PREFIX/drive_c/Program Files (x86)/Splashtop/Splashtop Remote/Client for RMM/clientoobe.exe"

ver=$(wine --version 2>/dev/null | sed 's/^wine-//; s/ .*//')
major=${ver%%.*}; minor=$(echo "$ver" | cut -d. -f2)
if [ "$major" -lt 9 ] || { [ "$major" -eq 9 ] && [ "${minor:-0}" -lt 3 ]; }; then
  echo "ERROR: wine $ver is too old. Need >= 9.3 (WineHQ bug #56244)." >&2
  echo "       Install winehq-staging from dl.winehq.org - see README." >&2
  exit 1
fi
echo "wine $ver OK"

[ -f "$CLIENT" ] || { echo "ERROR: client not found at $CLIENT" >&2
                      echo "       Install it first: WINEPREFIX=$PREFIX wine SplashtopRMM.exe /s" >&2; exit 1; }
echo "client found"

mkdir -p "$HOME/bin" "$HOME/.local/share/applications"
install -m 755 splashtop-rmm-handler "$HOME/bin/splashtop-rmm-handler"
sed "s|__HOME__|$HOME|g" splashtop-rmm.desktop.template \
  > "$HOME/.local/share/applications/splashtop-rmm.desktop"

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
xdg-mime default splashtop-rmm.desktop x-scheme-handler/st-rmm

echo
echo "Registered: $(xdg-mime query default x-scheme-handler/st-rmm)"
echo "Test with:  xdg-open 'st-rmm://PLUMBING-TEST-12345' && cat $PREFIX/handler.log"
