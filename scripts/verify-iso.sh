#!/usr/bin/env bash
# Prueft die gebaute ISO auf Inhalt, bevor man sie auf einen Stick schreibt.
# Nutzung: ./scripts/verify-iso.sh [pfad/zur.iso]
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ISO="${1:-$(ls -t "$ROOT"/out/*.iso 2>/dev/null | head -1)}"
[ -r "$ISO" ] || { echo "Keine ISO gefunden."; exit 1; }
OK=0; BAD=0
ok(){ printf '  \033[32mok\033[0m    %s\n' "$*"; OK=$((OK+1)); }
bad(){ printf '  \033[31mFEHLT\033[0m %s\n' "$*"; BAD=$((BAD+1)); }

echo "=== ISO ==="
printf '  Datei:  %s\n  Groesse: %s\n' "$(basename "$ISO")" "$(du -h "$ISO" | cut -f1)"

echo "=== 1. Bootfaehigkeit ==="
xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null | grep -qi "El Torito" \
  && ok "El-Torito-Bootkatalog vorhanden" || bad "kein El-Torito-Bootkatalog"
LIST="$(xorriso -indev "$ISO" -find / -type f 2>/dev/null)"
echo "$LIST" | grep -q "vmlinuz-linux-leon"          && ok "vmlinuz-linux-leon"          || bad "vmlinuz-linux-leon"
echo "$LIST" | grep -q "initramfs-linux-leon.img"    && ok "initramfs-linux-leon.img"    || bad "initramfs-linux-leon.img"
echo "$LIST" | grep -q "vmlinuz-linux-cachyos-lts"   && ok "LTS-Rettungskernel"          || bad "LTS-Rettungskernel"
echo "$LIST" | grep -q "airootfs.sfs"                && ok "airootfs.sfs"                || bad "airootfs.sfs"
echo "$LIST" | grep -qi "efi"                        && ok "EFI-Verzeichnis"             || bad "EFI-Verzeichnis"

echo "=== 2. Inhalt des Live-Dateisystems ==="
# NICHT mktemp -d: /tmp ist eine tmpfs (RAM). Ein 6,8-GB-squashfs passt da
# nicht hinein, die Extraktion wird stillschweigend abgeschnitten - und ein
# abgeschnittenes squashfs hat keine Verzeichnistabelle mehr (die steht am
# Dateiende), also findet unsquashfs -l gar nichts.
TMP="$(mktemp -d "$ROOT/work/verify.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
xorriso -osirrox on -indev "$ISO" -extract /arch/x86_64/airootfs.sfs "$TMP/airootfs.sfs" >/dev/null 2>&1
if [ -s "$TMP/airootfs.sfs" ]; then
  ok "airootfs.sfs extrahiert ($(du -h "$TMP/airootfs.sfs" | cut -f1))"
  # Liste in eine DATEI, nicht in eine Variable mit Pipe:
  # "echo \"$SQ\" | grep -q" bricht unter "set -o pipefail" falsch ab.
  # grep -q beendet sich beim ersten Treffer, echo bekommt SIGPIPE und
  # endet mit Fehlercode - pipefail meldet dann genau diesen Fehlercode,
  # ein TREFFER wird also als Fehlschlag gewertet.
  LST="$TMP/list.txt"
  unsquashfs -l "$TMP/airootfs.sfs" > "$LST" 2>/dev/null
  for f in \
    "usr/local/bin/gpu-mode" "usr/local/bin/gpu-offload-sync" "usr/local/bin/victus" \
    "usr/local/bin/cachy-install" "usr/local/bin/switch-to-v4" "usr/local/bin/postinstall-8845hs" \
    "etc/gpu-offload.d/apps.list" "etc/modprobe.d/nvidia-power.conf" \
    "etc/modprobe.d/nvidia-blacklist-nouveau.conf" "etc/default/grub" \
    "etc/sysctl.d/99-leon.conf" "etc/systemd/zram-generator.conf" \
    "usr/local/share/cachy-install/settings_offline.conf" \
    "usr/local/share/cachy-install/unpackfs.conf" \
    "etc/skel/.config/uwsm/env-hyprland" \
    "usr/bin/hashcat" "usr/bin/hyprland" "usr/bin/ghidra" "usr/bin/VirtualBox" \
    "usr/bin/docker" "usr/bin/mold" "usr/bin/ccache" ; do
    if grep -qiF "squashfs-root/$f" "$LST"; then ok "$f"; else bad "$f"; fi
  done
  echo "  --- Kernelmodule im Live-System ---"
  grep -oE "lib/modules/[^/]+" "$LST" | sort -u | sed 's/^/    /' | head
  echo "  --- NVIDIA-Module ---"
  grep -oE "nvidia[a-z_-]*\.ko[a-z.]*" "$LST" | sort -u | sed 's/^/    /' | head
  echo "  --- sshd-Autostart (darf NICHT da sein) ---"
  if grep -qF "multi-user.target.wants/sshd.service" "$LST"; then
    bad "sshd.service ist autostart-aktiv"
  else ok "sshd startet nicht automatisch"; fi
else
  bad "airootfs.sfs konnte nicht extrahiert werden"
fi

echo
echo "  $OK ok, $BAD fehlend"
[ "$BAD" -eq 0 ] && echo "  ISO sieht vollstaendig aus." || echo "  -> Fehlende Punkte pruefen."
