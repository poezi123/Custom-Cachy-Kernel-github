#!/usr/bin/env bash
# Schreibt die gebaute ISO auf einen USB-Stick.
#
# Ohne Argument sucht das Skript selbst nach Wechseldatentraegern und laesst
# dich waehlen. Interne Platten koennen dabei nicht getroffen werden: es
# akzeptiert nur Geraete, die USB sind, als removable gemeldet werden und
# nirgends als System-Dateisystem eingehaengt sind.
#
#   ./scripts/write-usb.sh              # Stick automatisch finden
#   ./scripts/write-usb.sh /dev/sdd     # Geraet vorgeben
#   ./scripts/write-usb.sh /dev/sdd --yes   # ohne Rueckfrage (Vorsicht)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PROJECT_ROOT:-$(dirname "$REPO")}"

red(){ printf '\033[31m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }
die(){ red "ABBRUCH: $*"; exit 1; }

DEV=""; ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    --yes|-y) ASSUME_YES=1 ;;
    /dev/*)   DEV="$a" ;;
    *)        die "unbekanntes Argument: $a" ;;
  esac
done

# --- ISO finden und pruefen -----------------------------------------------
ISO="$(ls -t "$ROOT"/out/*.iso 2>/dev/null | head -1 || true)"
[ -n "$ISO" ] || die "keine ISO in $ROOT/out gefunden."
ISO_SIZE=$(stat -c%s "$ISO")
printf 'ISO:  %s  (%s)\n' "$(basename "$ISO")" "$(numfmt --to=iec "$ISO_SIZE")"

if [ -r "$ROOT/out/SHA256SUMS" ]; then
  printf 'Pruefsumme ... '
  if (cd "$ROOT" && sha256sum -c out/SHA256SUMS >/dev/null 2>&1); then grn "ok"
  else die "Pruefsumme stimmt nicht. Die ISO ist beschaedigt - nicht schreiben."; fi
fi

# --- Kandidaten suchen ------------------------------------------------------
is_safe_target() {   # $1 = /dev/sdX
  local d="${1#/dev/}" 
  [ -b "/dev/$d" ] || return 1
  [ "$(cat "/sys/block/$d/removable" 2>/dev/null)" = "1" ] || return 1
  [ "$(lsblk -dn -o TRAN "/dev/$d" 2>/dev/null)" = "usb" ] || return 1
  # Kein Geraet, auf dem ein Systemverzeichnis liegt
  local mp
  while read -r mp; do
    case "$mp" in /|/boot|/boot/efi|/home|/var|/usr|/nix) return 1 ;; esac
  done < <(lsblk -ln -o MOUNTPOINT "/dev/$d" 2>/dev/null | grep -v '^$')
  return 0
}

if [ -z "$DEV" ]; then
  mapfile -t CAND < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' \
                      | while read -r d; do is_safe_target "$d" && echo "$d"; done)
  [ "${#CAND[@]}" -gt 0 ] || die "kein Wechseldatentraeger gefunden. Stick eingesteckt?"
  if [ "${#CAND[@]}" -eq 1 ]; then
    DEV="${CAND[0]}"
  else
    echo; echo "Mehrere Wechseldatentraeger gefunden:"
    for i in "${!CAND[@]}"; do
      printf '  [%d] %s\n' "$i" "$(lsblk -dn -o NAME,SIZE,MODEL,SERIAL "${CAND[$i]}")"
    done
    read -rp "Nummer: " n
    DEV="${CAND[$n]:-}"; [ -n "$DEV" ] || die "ungueltige Auswahl."
  fi
fi

# --- Ziel absichern ---------------------------------------------------------
is_safe_target "$DEV" || die "$DEV ist kein Wechseldatentraeger (oder traegt ein Systemverzeichnis). Verweigert."
DEV_SIZE=$(blockdev --getsize64 "$DEV" 2>/dev/null || cat "/sys/block/${DEV#/dev/}/size" | awk '{print $1*512}')
[ "$DEV_SIZE" -ge "$ISO_SIZE" ] || die "$DEV ist zu klein ($(numfmt --to=iec "$DEV_SIZE") < $(numfmt --to=iec "$ISO_SIZE"))."

echo
ylw "Ziel wird VOLLSTAENDIG ueberschrieben:"
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,SERIAL,MOUNTPOINT "$DEV" | sed 's/^/  /'
USED=$(lsblk -ln -o MOUNTPOINT "$DEV" | grep -v '^$' | head -3)
[ -n "$USED" ] && { echo "  aktuell eingehaengt unter:"; echo "$USED" | sed 's/^/    /'; }
echo

if [ "$ASSUME_YES" -ne 1 ]; then
  read -rp "Wirklich $DEV ueberschreiben? Tippe JA: " ans
  [ "$ans" = "JA" ] || die "abgebrochen."
fi

# --- Schreiben --------------------------------------------------------------
echo; echo ">>> Haenge Partitionen aus ..."
for p in $(lsblk -ln -o NAME "$DEV" | tail -n +2); do
  sudo umount "/dev/$p" 2>/dev/null && echo "    /dev/$p ausgehaengt" || true
done

echo ">>> Schreibe (bei USB 2.0 dauert das 10-25 Minuten) ..."
sudo dd if="$ISO" of="$DEV" bs=4M status=progress oflag=sync
echo ">>> sync ..."
sync

# --- Zurueckgelesen vergleichen --------------------------------------------
echo ">>> Pruefe das Geschriebene ..."
EXPECT=$(sha256sum "$ISO" | cut -d' ' -f1)
ACTUAL=$(sudo dd if="$DEV" bs=4M count=$(( (ISO_SIZE + 4194303) / 4194304 )) \
         iflag=fullblock status=none | head -c "$ISO_SIZE" | sha256sum | cut -d' ' -f1)
echo
if [ "$EXPECT" = "$ACTUAL" ]; then
  grn "Stick geschrieben und verifiziert. Du kannst ihn abziehen."
else
  red "Die zurueckgelesenen Daten weichen ab!"
  echo "  erwartet: $EXPECT"
  echo "  gelesen : $ACTUAL"
  echo "  Nochmal schreiben, oder einen anderen Stick nehmen."
  exit 1
fi
