#!/usr/bin/env bash
# Faehrt die restliche Kette unbeaufsichtigt durch:
#   Kernel abwarten -> Config verifizieren -> lokales Repo -> ISO -> ISO verifizieren
#
# Laeuft abgekoppelt (setsid/nohup), damit abgebrochene Vordergrundbefehle die
# Kette nicht unterbrechen. Fortschritt: tail -f work/pipeline.log
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PROJECT_ROOT:-$(dirname "$REPO")}"
LOG="$ROOT/work/pipeline.log"
mkdir -p "$ROOT/work"
step(){ printf '\n===== %s  [%s] =====\n' "$1" "$(date +%H:%M:%S)"; }
exec >>"$LOG" 2>&1

step "Pipeline gestartet"

# --- 1) Auf den Kernel-Build warten ---------------------------------------
if docker ps -q --filter name=linux-leon-build | grep -q .; then
  step "Warte auf laufenden Kernel-Build"
  RC="$(docker wait linux-leon-build)"
  echo "Kernel-Container beendet, Exit-Code: $RC"
else
  echo "Kein laufender Kernel-Build."
fi

shopt -s nullglob
PKGS=("$ROOT"/out/linux-leon*.pkg.tar.zst)
if [ ${#PKGS[@]} -eq 0 ]; then
  step "ABBRUCH: keine linux-leon-Pakete in out/"
  echo "Letzte Zeilen des Kernel-Logs:"
  docker logs --tail 40 linux-leon-build 2>&1 || true
  exit 1
fi
step "Kernelpakete vorhanden"
ls -lh "${PKGS[@]}"

# --- 2) Kernel-Config verifizieren ----------------------------------------
step "Kernel-Config gegen Soll-Liste pruefen"
CFG="$ROOT/work/config.built"
# Die .config steckt im HEADERS-Paket unter usr/lib/modules/<ver>/build/.config,
# nicht im Hauptpaket.
HDR="$(printf '%s\n' "${PKGS[@]}" | grep 'headers' | head -1)"
tar -I zstd -xOf "$HDR" --wildcards '*/build/.config' > "$CFG" 2>/dev/null || true
if [ -s "$CFG" ]; then
  "$REPO/scripts/verify-kernel-config.sh" "$CFG"
else
  echo "WARNUNG: .config konnte nicht aus dem Paket extrahiert werden."
  echo "Inhalt (Auszug):"; tar -I zstd -tf "$MAIN" | grep -iE "config" | head
fi

# --- 3) ISO bauen ----------------------------------------------------------
step "ISO bauen"
PROJECT_ROOT="$ROOT" "$REPO/scripts/build-iso.sh"
RC=$?
if [ "$RC" -ne 0 ]; then
  step "ISO-Build fehlgeschlagen (Exit $RC)"
  exit "$RC"
fi

# --- 4) ISO verifizieren ---------------------------------------------------
step "ISO verifizieren"
PROJECT_ROOT="$ROOT" "$REPO/scripts/verify-iso.sh"

step "Pipeline fertig"
ls -lh "$ROOT"/out/*.iso 2>/dev/null
