# Was ich am CachyOS-Profil ändern musste

Das Profil stammt von [CachyOS-Live-ISO](https://github.com/CachyOS/CachyOS-Live-ISO).
Weil hier **Live-System == installiertes System** gilt, wandert jeder Default
unverändert auf die Platte. Für eine Wegwerf-Live-ISO sind ein paar davon
vertretbar — für ein Arbeitsgerät nicht.

## Passwortloses Root-SSH

`airootfs/etc/shadow` enthält `root::14871::::::` — das leere Feld zwischen den
ersten beiden `:` ist ein leeres Passwort. Dazu `PermitRootLogin yes` plus
`PasswordAuthentication yes`, und `sshd.service` war autostart-aktiv.

Wer im selben Netz sitzt, loggt sich als root ohne Passwort ein. Bei
Standard-Live-ISOs bekannt und gewollt; auf einem Laptop, der in fremden WLANs
bootet, nicht. Und die `sshd_config` hätte über Live==Installed die Platte
erreicht.

**Fix:** kein sshd-Autostart mehr (`systemctl start sshd` bei Bedarf),
Config auf Pubkey-only, `PermitEmptyPasswords no`.

Die leeren Passwörter in `shadow` bleiben — sie gelten nur für die
Live-Sitzung, Calamares legt beim Installieren einen echten Benutzer an.
**Trag da nie einen echten Hash ein**, die Datei liegt im öffentlichen Repo.

## Ein nouveau-Fallback, der CUDA still abgeschaltet hätte

`etc/modprobe.d/nvidia-loader.conf` leitete jedes `modprobe nvidia` auf einen
Loader um, der per `chwd --list` nach dem Paket **`nvidia-open-dkms`** sucht und
sonst nouveau lädt.

Wir liefern das NVIDIA-Modul aber *im Kernelpaket*, nicht als DKMS-Paket. Der
Loader hätte es nicht erkannt und wäre auf nouveau gefallen: kein CUDA, kein
OpenCL, hashcat ohne die 4060. Das System bootet dabei völlig normal — nur die
GPU-Beschleunigung fehlt.

**Fix:** Loader raus, nouveau hart geblacklistet. Die Hardware steht fest, die
Indirektion hat hier keinen Zweck.

## Der Installer hätte tcpdump und cmake wieder deinstalliert

Calamares ruft in `shellprocess@before` das Skript `/usr/local/bin/removeun`
auf. Dessen Liste enthielt neben echten Live-Artefakten auch `tcpdump`,
`cmake`, `extra-cmake-modules`, `squashfs-tools`, `gparted`, `memtest86+` und
`arch-install-scripts`.

**Fix:** `removeun` neu geschrieben — entfernt werden nur Calamares-Pakete,
`mkinitcpio-archiso`, `clonezilla` und ähnliches. Der Security-, Dev- und
Recovery-Stack bleibt.

## Der Standard-Installer war der Online-Installer

`calamares-online.sh` setzt `mode="online"`. Der Online-Pfad zeigt eine
Desktop-Auswahl und holt Pakete frisch aus dem Netz — hätte also genau unser
Setup verworfen. Dazu fehlte in `settings_offline.conf` die Modulinstanz
`greetd` samt Sequenzschritt; die gibt es nur in der Online-Variante.

**Fix:** `/usr/local/bin/cachy-install` mit `mode="offline"` als Standardweg,
plus `.desktop`-Eintrag. Der greetd-Schritt ist in unsere
`settings_offline.conf` eingefügt.

Kleinigkeit am Rande: `vmtoolsd`, `vmware-vmblock-fuse`, `hv_*` und
`vboxservice` waren autostart-aktiv. Das sind Gast-Tools für den Betrieb
*innerhalb* einer VM — der Laptop ist VirtualBox-Host. Symlinks entfernt.

## Was bewusst nicht gehärtet ist

**Kein erzwungener Lockdown.** Gebaut, aber auf `FORCE_NONE`. Lockdown würde
eBPF-Tracing, `/dev/mem`, `kexec` und unsignierte Module blockieren — also
genau das Werkzeug, das hier gebraucht wird. Mit Secure Boot nachrüstbar.

**`yama.ptrace_scope = 1`, nicht 2 oder 3.** gdb kann selbst gestartete
Prozesse debuggen; für Attach an fremde PIDs braucht es `sudo`. Bei 2+ wäre
Reverse Engineering im Alltag unbrauchbar.

**`perf_event_paranoid = 1`.** Profiling ohne root. Auf einem Einzelplatzgerät
vertretbar, auf Mehrbenutzersystemen wäre 2 richtig.
