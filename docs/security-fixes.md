# Änderungen am geerbten CachyOS-Profil

Das Profil stammt von [CachyOS-Live-ISO](https://github.com/CachyOS/CachyOS-Live-ISO).
Weil hier **Live-System == installiertes System** gilt (Calamares offline/`unpackfs`),
wandert alles aus dem Live-Profil unverändert auf die Platte. Mehrere Defaults, die
für eine Wegwerf-Live-ISO vertretbar sind, sind das für ein Arbeitsgerät nicht.

## 1. Passwortloses Root-SSH

**Gefunden:** `airootfs/etc/shadow` enthält `root::14871::::::` — das leere Feld
zwischen den ersten beiden `:` ist ein **leeres Passwort**. Dazu:

```
# etc/ssh/sshd_config.d/10-archiso.conf (Original)
PasswordAuthentication yes
PermitRootLogin yes
```

und `sshd.service` war per Symlink in `multi-user.target.wants` autostart-aktiv.

**Wirkung:** Wer im selben Netz ist, loggt sich als root ohne Passwort ein.
Bei Standard-Live-ISOs bekannt; auf einem Laptop, der in fremden WLANs bootet,
nicht akzeptabel. Und via Live==Installed hätte die `sshd_config` das installierte
System erreicht.

**Fix:** `sshd.service`-Symlink entfernt (kein Autostart mehr, `systemctl start sshd`
bei Bedarf). `sshd_config.d/10-archiso.conf` ersetzt durch `PermitRootLogin no`,
`PasswordAuthentication no`, `PermitEmptyPasswords no`, nur Pubkey.

Die leeren Passwörter in `shadow` bleiben — sie gelten nur für die Live-Sitzung,
Calamares legt beim Installieren einen echten Benutzer an und entfernt `liveuser`.
**Trage dort niemals einen echten Hash ein**, die Datei liegt im Public Repo.

## 2. nouveau-Fallback hätte CUDA zerstört

**Gefunden:** `etc/modprobe.d/nvidia-loader.conf` leitete jedes `modprobe nvidia`
auf `/usr/local/bin/nvidia-module-loader` um. Dieser Loader sucht per
`chwd --list` nach dem Paket **`nvidia-open-dkms`** und lädt sonst **nouveau**.

**Wirkung:** Wir liefern das NVIDIA-Open-Modul *im Kernelpaket*
(`linux-leon-nvidia-open`), nicht als DKMS-Paket. Der Loader hätte es nicht
erkannt und wäre auf nouveau gefallen → kein CUDA, kein OpenCL, hashcat ohne
die 4060. Das ist ein stiller Fehler: das System bootet normal, nur die
GPU-Beschleunigung fehlt.

**Fix:** Loader und `nvidia-loader.conf` entfernt, stattdessen
`nvidia-blacklist-nouveau.conf` (nouveau hart aus). Die Hardware ist bekannt
und fest — die Indirektion hat hier keinen Zweck.

## 3. Der Installer hätte gewünschte Pakete deinstalliert

**Gefunden:** Calamares ruft in `shellprocess@before` das Skript
`/usr/local/bin/removeun` auf. Dessen Entfernliste enthielt u.a.:

```
tcpdump  cmake  extra-cmake-modules  squashfs-tools  gparted
memtest86+  arch-install-scripts  edk2-shell  syslinux  ...
```

**Wirkung:** `tcpdump` (Security-Stack) und `cmake` (Dev-Toolchain) wären von der
frisch installierten Platte geflogen.

**Fix:** `removeun` neu geschrieben. Entfernt werden nur echte Live-Artefakte
(Calamares-Pakete, `mkinitcpio-archiso`, `clonezilla`, …). Alles aus dem
Security-, Dev- und Recovery-Stack bleibt.

## 4. Offline-Installation ohne Greeter-Konfiguration

**Gefunden:** `settings_offline.conf` enthielt weder die Modulinstanz `greetd`
noch den Schritt `shellprocess@greetd` — beides gibt es nur in
`settings_online.conf`. Dieses Skript kopiert die noctalia-greeter-Konfiguration
nach `/etc/greetd/config.toml` und richtet den `greeter`-Benutzer ein.

**Wirkung:** Nach einer Offline-Installation hätte greetd keine passende
Konfiguration gehabt.

**Fix:** Modulinstanz und Sequenzschritt in unsere `settings_offline.conf`
eingefügt (liegt als Overlay in `airootfs/usr/share/calamares/`).

## 5. Der Standard-Installer war der Online-Installer

**Gefunden:** `calamares-online.sh` setzt `mode="online"` und kopiert
`settings_online.conf`. Der Online-Pfad zeigt eine Desktop-Auswahl und installiert
Pakete frisch aus dem Netz.

**Wirkung:** Genau das hätte unser Setup verworfen — der Sinn dieser ISO ist, das
Live-System zu klonen.

**Fix:** `/usr/local/bin/cachy-install` (`mode="offline"`) plus `.desktop`-Eintrag
als Standardweg.

## 6. VM-Gast-Dienste auf einem Host-System

**Gefunden:** `vmtoolsd`, `vmware-vmblock-fuse`, `hv_{fcopy,kvp,vss}_daemon` und
`vboxservice` waren autostart-aktiviert. Das sind Gast-Tools für den Betrieb
*innerhalb* einer VM. Der Laptop ist VirtualBox-**Host**.

**Fix:** Symlinks entfernt.

## Was bewusst NICHT gehärtet wurde

- **Kein erzwungener Lockdown.** `SECURITY_LOCKDOWN_LSM` ist gebaut, aber auf
  `FORCE_NONE`. Lockdown würde eBPF-Tracing, `/dev/mem`, `kexec` und unsignierte
  Module blockieren — also genau die Werkzeuge, die hier gebraucht werden.
  Bei aktiviertem Secure Boot nachrüstbar.
- **`kernel.yama.ptrace_scope = 1`**, nicht 2 oder 3. gdb kann selbst gestartete
  Prozesse debuggen; für Attach an fremde PIDs braucht es `sudo`. Bei 2+ wäre
  Reverse Engineering im Alltag unbrauchbar.
- **`kernel.perf_event_paranoid = 1`.** Erlaubt Profiling ohne root. Auf einem
  Einzelplatzgerät vertretbar, auf Mehrbenutzersystemen wäre 2 richtig.
