#!/usr/bin/env bash
# Baut die ISO. Voraussetzung: build-kernel.sh ist durchgelaufen und die
# linux-leon-Pakete liegen in out/.
set -euo pipefail
# REPO = dieses Repository, ROOT = das Arbeitsverzeichnis daneben (out/, work/, cache/).
# Beides aus der Skriptposition ableiten, damit das Repo beliebig heissen darf.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PROJECT_ROOT:-$(dirname "$REPO")}"
PROFILE="$REPO/iso-profile"
REPO="$ROOT/repo"
WORK="$ROOT/work"
OUT="$ROOT/out"

# --- 1) Lokales Pacman-Repo aus den Kernelpaketen bauen -------------------
mkdir -p "$REPO" "$WORK" "$OUT" "$ROOT/cache/pacman"
shopt -s nullglob
PKGS=("$OUT"/linux-leon*.pkg.tar.zst)
if [ ${#PKGS[@]} -eq 0 ]; then
  echo "FEHLER: keine linux-leon-Pakete in $OUT - zuerst build-kernel.sh laufen lassen." >&2
  exit 1
fi
cp -u "${PKGS[@]}" "$REPO"/
echo ">>> Lokales Repo aus ${#PKGS[@]} Paketen:"
printf '    %s\n' "${PKGS[@]##*/}"

docker run --rm -i \
  -v "$REPO:/localrepo" \
  cachy-builder:v2 bash -euo pipefail -c '
    cd /localrepo
    rm -f leon-local.db* leon-local.files*
    repo-add leon-local.db.tar.zst ./*.pkg.tar.zst >/dev/null
    echo ">>> Repo-Datenbank erzeugt."
  '

# --- 2) ISO bauen ---------------------------------------------------------
# --privileged: mkarchiso braucht Loop-Devices und mount im Container.
echo ">>> mkarchiso startet (das dauert)."
# cachyos-hello liest /etc/version-tag und prueft es gegen
# https://cachyos.org/versions.json. Fehlt die Datei, haelt es die ISO fuer
# einen Testing-Build, meldet "Testing-ISOs sind nicht stabil und nicht zum
# Verwenden geeignet" und startet den Installer gar nicht erst.
# Upstream schreibt die Datei in util-iso.sh (generate_version_tag); unser
# Build ruft util-iso.sh nicht auf, also hier - mit derselben Version, die
# profiledef.sh fuer den ISO-Namen benutzt.
ISO_VERSION="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
echo ">>> ISO-Version: $ISO_VERSION"

docker run --rm -i --privileged \
  -e ISO_VERSION="$ISO_VERSION" \
  -v "$PROFILE:/profile:ro" \
  -v "$REPO:/localrepo:ro" \
  -v "$WORK:/work" \
  -v "$OUT:/out" \
  -v "$ROOT/cache/pacman:/var/cache/pacman/pkg" \
  cachy-builder:v2 bash -euo pipefail -c '
    # us.cachyos.org liefert 404 auf Dateien, die seine DB kennt (nicht synchron).
    # pacman weicht zwar auf andere Mirrors aus, verliert dabei aber Zeit.
    # mirror.cachyos.org fehlt in der ausgelieferten Liste - nach vorne damit.
    sudo sed -i "/us\.cachyos\.org/d" \
      /etc/pacman.d/cachyos-mirrorlist /etc/pacman.d/cachyos-v3-mirrorlist
    sudo sed -i "1i Server = https://mirror.cachyos.org/repo/\$arch/\$repo" \
      /etc/pacman.d/cachyos-mirrorlist
    sudo sed -i "1i Server = https://mirror.cachyos.org/repo/\$arch_v3/\$repo" \
      /etc/pacman.d/cachyos-v3-mirrorlist

    # Docker legt die Loop-Geraeteknoten nicht an - losetup findet zwar eine
    # freie Nummer, laeuft dann aber in "device node /dev/loop0 is lost".
    # mkarchiso braucht sie fuer das FAT-Image der EFI-Partition.
    for i in $(seq 0 15); do sudo mknod -m 660 /dev/loop$i b 7 $i 2>/dev/null || true; done
    sudo chgrp disk /dev/loop* 2>/dev/null || true

    sudo cp -r /profile /tmp/profile        # mkarchiso schreibt ins Profil

    # cachyos-calamares-next 3.4.2-13 wurde am 13.08.2026 gebaut und ist gegen
    # boost 1.91 gelinkt. boost-libs im Repo steht seit dem 19.08. auf 1.92,
    # und "depend = boost-libs" ist unversioniert - pacman nimmt also 1.92, der
    # Soname passt nicht mehr, und Calamares startet gar nicht:
    #   libboost_python314.so.1.91.0: cannot open shared object file
    # Das trifft jede CachyOS-ISO, die derzeit gebaut wird; upstream hat
    # Calamares nach dem boost-Bump nicht neu gebaut.
    # Bis das behoben ist, legen wir die versionierten 1.91-Bibliotheken
    # daneben. Nur Dateien mit Versionssuffix, keine Symlinks - deshalb
    # kollidiert nichts mit 1.92, und beide Sonames existieren parallel.
    BOOST=boost-libs-1.91.0-2-x86_64.pkg.tar.zst
    curl -sL --fail -o "/tmp/$BOOST" \
      "https://archive.archlinux.org/packages/b/boost-libs/$BOOST"
    sudo bsdtar -xf "/tmp/$BOOST" -C /tmp/profile/airootfs "usr/lib/*.so.1.91.0"
    echo ">>> boost 1.91: $(find /tmp/profile/airootfs/usr/lib -name "*.so.1.91.0" | wc -l) Bibliotheken beigelegt."

    echo "$ISO_VERSION" | sudo tee /tmp/profile/airootfs/etc/version-tag >/dev/null
    echo "desktop"      | sudo tee /tmp/profile/airootfs/etc/edition-tag >/dev/null
    sudo mkarchiso -v -w /work -o /out /tmp/profile
  '

echo
echo ">>> Fertig:"
ls -lh "$OUT"/*.iso 2>/dev/null || echo "    keine ISO erzeugt - Log pruefen."
