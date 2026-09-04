#!/usr/bin/env bash
# Prueft das Repo auf Dinge, die nicht oeffentlich werden duerfen.
# Nutzung:  ./scripts/check-before-push.sh
# Als Hook: ln -sf ../../scripts/check-before-push.sh .git/hooks/pre-push
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
FAIL=0; WARN=0
red(){ printf '\033[31m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }

# Nur was Git tatsaechlich tracken wuerde (respektiert .gitignore)
if git rev-parse --git-dir >/dev/null 2>&1; then
  mapfile -t FILES < <(git ls-files --cached --others --exclude-standard)
else
  ylw "Kein Git-Repo - pruefe alle Dateien im Verzeichnis."
  mapfile -t FILES < <(find . -type f -not -path "./.git/*")
fi
printf 'Pruefe %d Dateien...\n\n' "${#FILES[@]}"

echo "── 1. Kryptomaterial ─────────────────────────────────────"
for f in "${FILES[@]}"; do
  case "$f" in
    *.key|*.pem|*.p12|*.pfx|*id_rsa*|*id_ed25519*|*id_ecdsa*|*secring*|*.gpg|*.kbx)
      red "  KEY?  $f"; FAIL=1 ;;
  esac
  if [ -f "$f" ] && head -c 2000 "$f" 2>/dev/null | grep -qE "BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY"; then
    red "  PRIVATE KEY im Inhalt: $f"; FAIL=1
  fi
done

echo "── 2. Credentials ────────────────────────────────────────"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  # Praezise Muster: es geht um Dateien, die tatsaechlich Zugangsdaten tragen.
  # Ein blosses *wpa_supplicant* wuerde auch die systemd-Units des Dienstes
  # treffen - die enthalten nichts Geheimes.
  case "$f" in
    */system-connections/*|*wpa_supplicant*.conf|*.env|*.netrc)
      red "  CREDS $f"; FAIL=1 ;;
  esac
  # Tokens: GitHub ghp_/github_pat_, AWS AKIA, generische api_key=
  if grep -qEn "(ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}|AKIA[0-9A-Z]{16})" "$f" 2>/dev/null; then
    red "  TOKEN $f"; FAIL=1
  fi
  if grep -qEin "(api[_-]?key|secret|passwo?rd|token)[\"' ]*[:=][\"' ]*[A-Za-z0-9/+_-]{16,}" "$f" 2>/dev/null; then
    ylw "  pruefen: moegliches Secret in $f"; WARN=1
  fi
done

echo "── 3. Passwort-Hashes in shadow ──────────────────────────"
for f in "${FILES[@]}"; do
  case "$f" in *shadow*)
    if grep -qE "^[^:]+:[^:!*]" "$f" 2>/dev/null; then
      red "  ECHTER HASH in $f - niemals pushen!"; FAIL=1
    else
      grn "  ok: $f (nur leere/gesperrte Passwoerter)"
    fi ;;
  esac
done

echo "── 4. Security-Arbeitsdaten ──────────────────────────────"
for f in "${FILES[@]}"; do
  case "$f" in
    *.cap|*.pcap|*.pcapng|*.hccapx|*.22000|*.potfile|*hashcat.pot*|*.hash|*.ntds|*.kdbx)
      red "  CAPTURE/HASHES $f - enthaelt fremde Daten"; FAIL=1 ;;
  esac
done

echo "── 5. Dateigroessen (GitHub: 100 MB hart, 50 MB Warnung) ─"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  S=$(stat -c%s "$f" 2>/dev/null || echo 0)
  if   [ "$S" -gt 104857600 ]; then red "  $((S/1048576)) MB  $f - GitHub lehnt >100MB ab"; FAIL=1
  elif [ "$S" -gt 52428800 ];  then ylw "  $((S/1048576)) MB  $f - besser als Release-Asset"; WARN=1; fi
done

echo "── 6. Identitaet ─────────────────────────────────────────"
if git rev-parse --git-dir >/dev/null 2>&1; then
  EMAIL=$(git config user.email || echo "")
  case "$EMAIL" in
    *noreply.github.com) grn "  ok: $EMAIL" ;;
    "") ylw "  git user.email nicht gesetzt"; WARN=1 ;;
    *) ylw "  Commits mit echter E-Mail: $EMAIL"
       ylw "     -> git config user.email '<id>+<user>@users.noreply.github.com'"; WARN=1 ;;
  esac
fi
# /home/liveuser (Live-ISO) und /home/builder (Build-Container) sind bewusst
# hartkodiert - das sind keine Benutzerpfade des Entwicklers.
HITS=$(grep -rlE "/home/(?!liveuser|builder)[a-z]+/|leon-mainpc" -P \
        --include="*.conf" --include="*.sh" --include="*.toml" --include="*.md" . 2>/dev/null \
        | grep -v check-before-push || true)
if [ -n "$HITS" ]; then
  ylw "  Hartkodierte Benutzerpfade/Hostnamen (durch \$HOME/\$USER ersetzen):"
  echo "$HITS" | head -5 | sed 's/^/     /'
  WARN=1
else
  grn "  keine hartkodierten Benutzerpfade"
fi

echo
if   [ "$FAIL" -ne 0 ]; then red "ABBRUCH - kritische Funde. Nicht pushen."; exit 1
elif [ "$WARN" -ne 0 ]; then ylw "Mit Warnungen durchgelaufen - bitte durchsehen."; exit 0
else grn "Sauber."; exit 0; fi
