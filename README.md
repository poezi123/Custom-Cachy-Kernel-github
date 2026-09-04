# Custom-Cachy-Kernel

Eine bootbare CachyOS-ISO, zugeschnitten auf
**HP Victus 16-s1902ng** — Ryzen 7 8845HS (Zen 4), Radeon 780M, RTX 4060 Laptop —
mit eigenem Kernel, Hyprland und einem Security-/Dev-Stack.

Kernidee: die ISO wird über den **Offline-Modus** von Calamares installiert,
der `airootfs.sfs` 1:1 auf die Platte entpackt.

> **Live-System == installiertes System.** Was in der ISO steckt, landet exakt
> so auf dem Laptop. Keine Nachinstallation, keine Desktop-Auswahl.

Das hat eine Kehrseite, die man kennen muss: **jeder Default des Live-Profils
wird zum Default des Arbeitsgeräts.** Mehrere davon mussten korrigiert werden —
siehe [`docs/security-fixes.md`](docs/security-fixes.md).

## Status

Gebaut und getestet: Kernel-Config **37/37**, ISO-Inhalt **30/30**, in QEMU bis
zum Hyprland-Desktop gebootet, Laufzeitwerte über die serielle Konsole belegt.
Details und die Grenzen des Tests: [`docs/verification.md`](docs/verification.md).

## Der Kernel: `linux-leon`

Fork von [linux-cachyos](https://github.com/CachyOS/linux-cachyos) 7.2.3 mit
eigenem `pkgbase`, damit Repo-Updates ihn nicht überschreiben.

| | |
|---|---|
| Scheduler | BORE |
| Optimierung | `-march=znver4`, `-O3`, Clang **ThinLTO** |
| Preemption | `PREEMPT_DYNAMIC` — `full` ⇄ `lazy` zur Laufzeit umschaltbar |
| Tick | 1000 Hz, `NO_HZ_IDLE` |
| NVIDIA | Open-Modul **im Kernelpaket** — kein DKMS, kein Versions-Mismatch |
| Härtung | Landlock, Yama, AppArmor, BPF-LSM, kein erzwungener Lockdown |
| Mitigations | vollständig aktiv |

Begründung jeder Option: [`docs/kernel-rationale.md`](docs/kernel-rationale.md).

## GPU: Hybrid mit automatischem Offload

Automatisches Umschalten bei Last gibt es unter Linux nicht — PRIME-Offload wird
beim Prozessstart entschieden. Stattdessen:

- Die 4060 schläft in **D3cold** (~0.5 W statt ~12 W), die 780M treibt den Desktop.
- `/usr/local/lib/gpu-offload` liegt **vor** `/usr/bin` im `PATH`. Programme aus
  `/etc/gpu-offload.d/apps.list` (Steam, hashcat, Blender, …) bekommen dort einen
  Shim und starten automatisch auf der 4060 — egal ob aus dem Terminal, aus
  Hyprland oder über eine `.desktop`-Datei.
- Einzelfall überschreiben: `GPU_OFFLOAD=0 steam`
- Ganze Session auf die dGPU: `sudo gpu-mode nvidia` (Neuanmeldung nötig)
- Maximale Laufzeit: `sudo gpu-mode integrated` (dGPU aus, kein CUDA)
- Status: `gpu-mode status`

## Thermik & Lüfter: nativ, kein nbfc

Kernel 7.2 unterstützt **Victus-S-Boards** im `hp-wmi`-Treiber direkt:
`platform_profile`, getrennte CPU-/GPU-Lüfterdrehzahlen und manuelles `pwm1`.

Der Hebel für Hashcat: im Profil `performance` schaltet der Treiber **CTGP**
und **PPAB** der 4060 frei — mehr TGP-Budget. Deshalb steht `hashcat` in
`/etc/gpu-offload.d/apps.list` mit `!perf` und startet über
`powerprofilesctl launch -p performance`. Das Profil gilt nur für die Laufzeit.

```bash
victus status          # Board-ID, Profil, Lüfter, Temperaturen
sudo victus perf       # Performance (CTGP/PPAB an)
sudo victus fan max
victus diagnose        # falls die Board-ID dem Treiber fehlt
```

Details: [`docs/victus-16-s.md`](docs/victus-16-s.md).

## Bauen

Läuft vollständig in Docker — der Host bleibt unberührt und braucht kein `sudo`.

```bash
docker build -f docker/Dockerfile.builder -t cachy-builder:v2 .
./scripts/build-kernel.sh     # ~90 min, erzeugt out/linux-leon-*.pkg.tar.zst
./scripts/build-iso.sh        # baut lokales Repo + ruft mkarchiso
```

**x86-64-v3, nicht v4:** `mkarchiso` führt beim Bauen Binaries aus dem
entstehenden System im chroot aus. Wird die ISO auf einer CPU ohne AVX-512
gebaut, stirbt ein v4-Build mit SIGILL. Auf dem Laptop danach:

```bash
sudo postinstall-8845hs   # Shims, Dienste, Gruppen, DKMS
sudo switch-to-v4         # Userspace auf AVX-512 hochziehen
```

## Layout

Die Build-Verzeichnisse liegen bewusst **neben** dem Repo, nicht darin — sonst
landen 7-GB-Artefakte in `git status`:

```
Kernel/                        <- Arbeitsverzeichnis
├── Custom-Cachy-Kernel-github/   <- dieses Repo
├── build/linux-leon/             <- PKGBUILD-Arbeitskopie
├── cache/{src,pkg,pacman,ccache} <- Downloads und ccache
├── out/                          <- fertige ISO und Pakete
├── repo/                         <- lokales Pacman-Repo
└── work/                         <- mkarchiso-Arbeitsverzeichnis
```

Die Skripte leiten beides aus ihrer eigenen Position ab (`scripts/..` = Repo,
eine Ebene höher = Arbeitsverzeichnis). Das Repo darf also beliebig heißen.
Mit `PROJECT_ROOT=/pfad` lässt sich das Arbeitsverzeichnis überschreiben.


| Pfad | Inhalt |
|---|---|
| `kernel/` | PKGBUILD + Config für `linux-leon` |
| `iso-profile/` | archiso-Profil: Paketliste, `pacman.conf`, GRUB, airootfs-Overlay |
| `scripts/` | Build-, Prüf- und Laufzeitskripte |
| `docker/` | Build-Container |
| `docs/` | Entscheidungen und Rationale |

Weitere Docs: [`kernel-rationale.md`](docs/kernel-rationale.md) · [`verification.md`](docs/verification.md) · [`security-fixes.md`](docs/security-fixes.md) · [`victus-16-s.md`](docs/victus-16-s.md)

## Auf einen Stick schreiben

```bash
./scripts/write-usb.sh          # sucht den Stick selbst
```

Das Skript prüft vorher die SHA256, akzeptiert nur Geräte die USB **und**
removable sind und kein Systemverzeichnis tragen, zeigt dir das Ziel und
verlangt ein getipptes `JA`. Nach dem Schreiben liest es zurück und
vergleicht die Prüfsumme.

## Was hier nicht liegt

Die gebaute ISO (~7 GB) und die Kernelpakete sind **nicht** im Repo — GitHub
deckelt Dateien bei 100 MB und Release-Assets bei 2 GB. Im Repo liegt das
Rezept; die ISO baut man sich in ~2 h selbst (siehe oben) oder lädt sie dort,
wo sie gehostet ist. `SHA256SUMS` zum Abgleich liegt bei.

## Vor dem Push

```bash
./scripts/check-before-push.sh
```

Sucht nach Keys, Credentials, echten Passwort-Hashes, Captures und zu großen
Dateien. Läuft auch in der CI.

## Lizenz

Abgeleitet von CachyOS: `linux-cachyos` (GPL-2.0-only) und CachyOS-Live-ISO
(GPL-3.0). Beides Copyleft — dieses Repo steht unter **GPL-3.0**.
