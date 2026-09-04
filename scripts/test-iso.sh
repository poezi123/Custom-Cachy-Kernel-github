#!/usr/bin/env bash
# Bootet die gebaute ISO in QEMU (UEFI) zum Testen.
#
#   ./scripts/test-iso.sh              KVM, bootet den LTS-Rettungskernel
#   ./scripts/test-iso.sh --znver4     TCG mit -cpu max (emuliert AVX-512),
#                                      damit auch linux-leon startet. SEHR langsam.
#   ./scripts/test-iso.sh --headless   ohne Fenster, serielle Konsole ins Log
set -euo pipefail
ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ISO="$(ls -t "$ROOT"/out/*.iso 2>/dev/null | head -1)"
[ -n "$ISO" ] || { echo "Keine ISO in $ROOT/out gefunden."; exit 1; }

OVMF_CODE=""
for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/ovmf/x64/OVMF_CODE.4m.fd \
         /usr/share/edk2-ovmf/x64/OVMF_CODE.fd; do
  [ -r "$c" ] && { OVMF_CODE="$c"; break; }
done
[ -n "$OVMF_CODE" ] || { echo "Keine OVMF-Firmware gefunden."; exit 1; }
OVMF_VARS_SRC="${OVMF_CODE%CODE*}VARS${OVMF_CODE##*CODE}"
[ -r "$OVMF_VARS_SRC" ] || OVMF_VARS_SRC="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

VARS="$ROOT/work/OVMF_VARS.test.fd"
mkdir -p "$ROOT/work"; cp -f "$OVMF_VARS_SRC" "$VARS"

ZNVER4=0; HEADLESS=0
for a in "$@"; do
  case "$a" in --znver4) ZNVER4=1;; --headless) HEADLESS=1;; esac
done

ARGS=(
  -machine q35
  -m 6G -smp 4
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,unit=1,file=$VARS"
  -cdrom "$ISO"
  -boot d
  -netdev "user,id=n0" -device "virtio-net-pci,netdev=n0"
)

if [ "$ZNVER4" = "1" ]; then
  # Kein KVM: der Host (Zen 2) kann kein AVX-512, das Gastmodell braucht es aber
  # fuer linux-leon. TCG emuliert es - funktioniert, ist aber zaeh.
  echo ">>> TCG-Modus mit -cpu max (AVX-512 emuliert). Sehr langsam."
  ARGS+=(-accel tcg -cpu max)
else
  echo ">>> KVM-Modus. Nur der LTS-Rettungskernel bootet hier (linux-leon ist znver4)."
  ARGS+=(-accel kvm -cpu host)
fi

if [ "$HEADLESS" = "1" ]; then
  LOG="$ROOT/work/qemu-serial.log"
  echo ">>> Headless, serielle Konsole -> $LOG"
  ARGS+=(-nographic -serial "file:$LOG")
else
  ARGS+=(-vga virtio -display gtk)
fi

echo ">>> ISO: $(basename "$ISO")  ($(du -h "$ISO" | cut -f1))"
exec qemu-system-x86_64 "${ARGS[@]}"
