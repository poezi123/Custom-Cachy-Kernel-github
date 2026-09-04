# Was darf ins Public Repo — und was nicht

## ✅ Gehört rein (das ist der eigentliche Wert des Repos)

| Pfad | Warum unbedenklich |
|---|---|
| `kernel/PKGBUILD`, `kernel/config` | Build-Rezept, keine Geheimnisse. Der Wert des Repos. |
| `kernel/config.generated` | Die fertige `.config` — dokumentiert exakt, was im Kernel steckt. Reproduzierbarkeit. |
| `iso-profile/**` | Paketliste, `profiledef.sh`, `pacman.conf`, GRUB/syslinux, airootfs-Overlay. |
| `docker/Dockerfile.builder` | Reproduzierbare Build-Umgebung. |
| `scripts/**` | Build-, Post-Install- und GPU-Skripte. |
| `configs/hypr/**` | Dotfiles. Vorher auf Pfade mit Benutzernamen prüfen. |
| `docs/**` | Design-Entscheidungen, Rationale, Benchmarks. |
| `README.md`, `LICENSE` | — |
| `SHA256SUMS` | Prüfsummen der Releases (nicht die Releases selbst). |
| `.github/workflows/**` | CI. Secrets dort nur als GitHub-Secrets referenzieren, nie inline. |

## 📦 Nicht ins Git, aber als GitHub **Release-Asset**

GitHub-Limits: **100 MB pro Datei im Repo**, **2 GB pro Release-Asset**.

- `*.iso` (~4–8 GB) → **überschreitet auch das Release-Limit.** Extern hosten
  (eigener Server, S3/R2, Torrent) und im Release nur Link + SHA256 hinterlegen.
- `linux-leon-*.pkg.tar.zst` (~150 MB) → Release-Asset, nicht Git.
- Niemals Git LFS für ISOs: das Bandbreiten-Kontingent ist sofort aufgebraucht.

## ⛔ Darf nirgendwo hin

**Kryptomaterial**
- Secure-Boot-/Signing-Keys, MOK, `sbctl`-Verzeichnis (auch wenn Secure Boot aktuell aus ist)
- GPG-Secret-Keys, `secring.*`
- SSH-Private-Keys, gesamtes `~/.ssh`
- LUKS-Header, Keyfiles

**Credentials & Identität**
- `/etc/NetworkManager/system-connections/*` — enthält **WLAN-PSKs im Klartext**
- `wpa_supplicant.conf`
- `/etc/shadow` mit echten Hashes → siehe Warnung unten
- API-Tokens (GitHub, Shodan, VirusTotal, Burp-Lizenz), `.env`
- `machine-id`, Host-UUIDs, Seriennummern

**Berufsspezifisch (Cybersecurity)**
- Captures und Handshakes: `*.cap`, `*.pcap`, `*.pcapng`, `*.hccapx`, `*.22000`
  → enthalten fremde Netze und fremde Daten. Auch "nur zum Testen" nicht.
- Hash-Dumps, `hashcat.potfile`, `~/.local/share/hashcat/`
- Wordlists aus Leaks (rockyou ist verbreitet, aber es sind echte Passwörter echter Menschen)
- Kunden-/Engagement-Daten, Scan-Ergebnisse, Reports
- Exploits/CVE-PoCs → gehören **nicht in dieses Repo**. Scope hier ist Kernel + ISO.
  Wenn du sie veröffentlichst, dann bewusst, getrennt und mit eigener Entscheidung.

## ⚠️ Graubereich — bewusst entscheiden

| Sache | Überlegung |
|---|---|
| **Deine echte E-Mail in Commits** | Landet dauerhaft öffentlich und wird abgegrast. Nutze die GitHub-noreply-Adresse: `git config user.email "<id>+<user>@users.noreply.github.com"` |
| **Hostname / Username in Configs** | `leon-mainpc`, `/home/leon/...` — harmlos, aber ein Fingerprint. In Dotfiles durch `$USER`/`$HOME` ersetzen. |
| **Exaktes Laptop-Modell** | Macht dich identifizierbarer. Bei einem hardware-spezifischen Repo aber inhaltlich notwendig — ist okay. |
| **Eigene hashcat-Rules/Masken** | Eigene Arbeit: unbedenklich. Geleakte Wordlists: nein. |
| **`linux-leon` Kernel-Config** | Zeigt deine Angriffsfläche (welche Module, welche Härtung). Bei einem Einzelgerät irrelevant, ich halte das für unbedenklich. |

## 🔴 Konkrete Warnung zu diesem Profil

Das von CachyOS geerbte `iso-profile/airootfs/etc/shadow` enthält aktuell:

```
root::14871::::::
liveuser::14871::::::
```

Das sind **leere Passwörter** (Feld zwischen den ersten beiden `:` ist leer).
Zusammen mit `etc/ssh/sshd_config.d/10-archiso.conf` (`PermitRootLogin yes`,
`PasswordAuthentication yes`) und aktiviertem `sshd.service` bedeutet das:
**passwortloses Root-SSH auf jedem Netz, in dem die Live-ISO bootet.**

Sobald du dort einen echten Hash einträgst, veröffentlichst du diesen Hash.
→ Setze niemals ein echtes Passwort in diese Datei. Siehe `docs/security-fixes.md`.

## Lizenz

`kernel/PKGBUILD` ist von [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos)
abgeleitet (**GPL-2.0-only**), das ISO-Profil von CachyOS-Live-ISO (**GPL-3.0**).
Beides sind Copyleft-Lizenzen — das Repo muss unter einer kompatiblen Lizenz stehen.
Herkunft im Header jeder abgeleiteten Datei vermerken.
