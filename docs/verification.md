# Was tatsächlich getestet wurde

Alles hier ist gemessen, nicht angenommen. Gebaut auf einem Ryzen 5 3600
(Zen 2), getestet in QEMU/KVM mit OVMF.

## Automatische Prüfungen

`scripts/verify-kernel-config.sh` gegen die `.config` aus dem gebauten
Headers-Paket: **37 von 37**. Geprüft werden BORE, PREEMPT_DYNAMIC, HZ 1000,
NO_HZ_IDLE, MZEN4, ThinLTO, THP madvise, HSA_AMD, eBPF/BTF, alle LSMs,
kprobes/ftrace, die Härtungsoptionen, AMD_PMC/PMF, amd_pstate, MGLRU, zram, BBR.

`scripts/verify-iso.sh`: **30 von 30**. Bootkatalog und EFI, beide Kernel mit
initramfs, und im squashfs alle eigenen Skripte und Configs plus `hashcat`,
`hyprland`, `ghidra`, `VirtualBox`, `docker`, `mold`, `ccache`. Und dass `sshd`
*nicht* autostart-aktiv ist.

## Boot

Die ISO bootet in QEMU über GRUB bis zum Hyprland-Desktop mit Noctalia-Shell —
Top-Bar, CachyOS-Hello, Terminal per `SUPER+Return`. Screenshots entstehen mit
`scripts/qemu-boot-test.py`.

Direkter Kernelstart mit serieller Konsole:

```
CachyOS 7.2.3-1-leon (ttyS0)
CachyOS login:
```

Keine Panics, Oopses oder Invalid-Opcode-Fehler.

## Laufzeitwerte im laufenden System

| | |
|---|---|
| `uname -a` | `7.2.3-1-leon #1 SMP PREEMPT_DYNAMIC` |
| `sched/preempt` | `(full) lazy` |
| `kernel.sched_bore` | `1` |
| zram | `/dev/zram0 zstd 3.8G`, Priorität 100 |
| LSM-Kette | `lockdown,capability,landlock,yama,apparmor,bpf` |
| `/sys/kernel/btf/vmlinux` | da, 10,8 MB |
| THP | `always [madvise] never` |
| TCP | `bbr` + `fq` |
| `modinfo nvidia` | `610.57.04` |
| yama / perf / kptr / inotify | `1 / 1 / 1 / 524288` |

`gpu-offload-sync` erzeugt die Shims korrekt; der hashcat-Shim endet mit
`exec powerprofilesctl launch -p performance -- /usr/bin/hashcat "$@"`.

## Zwei Annahmen, die sich als falsch erwiesen

**Der znver4-Kernel bootet sehr wohl auf Zen 2.** Ich war davon ausgegangen,
`-march=znver4` mache ihn auf älteren CPUs unbootbar. Falsch: der Kernel wird
mit `-mno-sse -mno-mmx -mno-avx` übersetzt, `-march` wirkt also nur auf
Scheduling und skalare Befehle — und da bringt Zen 4 gegenüber Zen 2 nichts
Neues. Praktische Folge: der echte Zielkernel ist lokal vollständig testbar.

**`vm.swappiness` wird per udev gesetzt, nicht per sysctl.** In
`99-leon.conf` stand 180, gemessen wurden 150. Ursache:

```
/usr/lib/udev/rules.d/30-zram.rules   (aus cachyos-settings)
ACTION=="change", KERNEL=="zram0", ... SYSCTL{vm.swappiness}="150"
```

Diese Regel läuft *nach* `systemd-sysctl` und gewinnt immer — alle anderen
Werte aus derselben Datei kamen korrekt an. Die wirkungslose Zeile ist raus.
Wer 180 will, legt `/etc/udev/rules.d/31-zram-swappiness.rules` an.

## Was der erste Boot auf echter Hardware ergab

Zwei Dinge, die QEMU nicht zeigen konnte, weil dort weder eine zweite GPU noch
ein Netzwerk-Check existiert. Beide sind gefixt, beide waren echte Blocker.

### Schwarzer Bildschirm, sporadisch

Von drei Boots kamen zwei nicht über die Bootmeldungen hinaus — kein Hyprland,
kein Greeter, schwarz. Der dritte lief durch. Sporadisch, nicht reproduzierbar.

Ursache: Aquamarine, Hyprlands Backend, nimmt das **erste** DRM-Gerät als
primäres. Welches das ist, entscheidet die Reihenfolge der Geräte-Enumeration,
und die ist nicht deterministisch. Das Victus 16-s hat **keinen MUX** — das
Panel hängt fest an der 780M, die 4060 hat keinen Ausgang. Fällt die
Enumeration auf die 4060, rendert der Compositor auf eine Karte ohne Display.

Der Hybrid-Zweig von `gpu-mode` setzte `AQ_DRM_DEVICES` bewusst nicht, mit dem
Kommentar „Hyprland wählt selbst (amdgpu primär)". Das war eine Annahme, keine
Messung — und sie stimmt in etwa einem von drei Boots nicht.

**Fix:** `gpu-primary-card` sucht über `/dev/dri/by-path/` die Karte mit
Treiber `amdgpu` — der by-path-Pfad hängt an der PCI-Adresse und ist stabil,
während die `cardN`-Nummer selbst das Problem ist. `gpu-primary.service`
schreibt sie vor `greetd.service` nach `/etc/environment.d/94-gpu-primary.conf`
und zusätzlich als Drop-in in die greetd-Unit: der Greeter startet, bevor eine
User-Session existiert, und liest `environment.d` nicht. Die Nummer 94 lässt
`gpu-mode nvidia` mit seiner `95-gpu-mode.conf` weiterhin gewinnen.

### Der Installer verweigerte den Start

cachyos-hello meldete „Du verwendest eine alte Testing ISO, Testing-ISOs sind
nicht stabil und nicht zum Verwenden geeignet" und startete Calamares nicht.

Ursache: cachyos-hello liest `/etc/version-tag` und prüft es gegen
`https://cachyos.org/versions.json`. Upstream schreibt die Datei in
`util-iso.sh` (`generate_version_tag`); unser Build ruft `util-iso.sh` nicht
auf, die Datei fehlte also komplett — und ohne Version gilt die ISO als
Testing-Build.

**Fix:** `build-iso.sh` schreibt `version-tag` und `edition-tag` in das
Profil, bevor `mkarchiso` läuft. Unabhängig davon zeigt
`/usr/local/bin/calamares-online.sh` — der Pfad, den cachyos-hello fest
verdrahtet aufruft — jetzt auf den Offline-Installer statt auf den
Online-Pfad, der das gesamte Setup verworfen hätte.

### Calamares startete nicht: boost-Soname

Nach dem version-tag-Fix kam der Installer bis zum `exec` und starb dort:

```
calamares: error while loading shared libraries:
libboost_python314.so.1.91.0: cannot open shared object file
```

Kein Fehler am Profil, sondern am CachyOS-Repo:

| Paket | Version | Gebaut |
|---|---|---|
| `cachyos-calamares-next` | 3.4.2-13 | 2026-08-13 |
| `boost-libs` | 1.92.0-1.1 | 2026-08-19 |

boost wurde sechs Tage nach Calamares angehoben, Calamares aber nie neu
gebaut. `depend = boost-libs` ist unversioniert, pacman installiert also 1.92,
und der Soname passt nicht mehr. Das trifft **jede** CachyOS-ISO, die in
diesem Zeitfenster gebaut wird — ein Neubau aus dem Repo hilft nicht, es ist
derselbe Build.

**Fix:** `build-iso.sh` holt `boost-libs-1.91.0-2` aus dem Arch-Archiv und
legt daraus nur die Dateien mit Versionssuffix (`*.so.1.91.0`, 48 Stück) ins
airootfs. Keine unversionierten Symlinks, also kein Konflikt mit 1.92 — beide
Sonames liegen nebeneinander. Sobald upstream Calamares gegen 1.92 neu baut,
kann der Block raus.

### Nach der Installation kein Bootloader

Erster echter Installationslauf: Calamares meldete Erfolg, danach bootete das
Gerät mit „please install an operating system on your hard disk". Ursache war
nicht die Partitionierung, sondern die Bootloader-Config: der Paket-Default
wählt den Bootloader über einen `packagechooser` (Default **limine**). Die
Offline-Sequenz hat keinen solchen Auswahlschritt, und limine ist gar nicht in
der ISO — nur `grub`. Also installierte Calamares **keinen** Bootloader.

**Fix:** `cachy-install` legt ein `bootloader.conf`-Override ab, das `grub`
erzwingt (`efiBootLoader: "grub"`, kein `packagechooser`-Verweis).
`installEFIFallback` bleibt an — GRUB landet zusätzlich auf dem
removable-Pfad `/EFI/BOOT/BOOTX64.EFI`, falls die HP-Firmware den
NVRAM-Eintrag verwirft. Bei der Installation die Option **Gesamte Festplatte
löschen** wählen, damit überhaupt eine EFI-Partition angelegt wird.

### Schwarzer Schirm, zweiter Anlauf

Der erste GPU-Fix (`gpu-primary.service` setzt `AQ_DRM_DEVICES` über
`environment.d` und ein greetd-Drop-in) griff auf der echten Hardware nicht.
Grund: `uwsm` startet Hyprland und baut dessen Umgebung selbst neu auf — es
reicht diese Variablen nicht an den Compositor durch. Dazu ließ `nvidia_drm`
mit `fbdev=1` die 4060 einen Framebuffer greifen, obwohl an ihr kein Display
hängt.

**Fix:** `fbdev=1` → `fbdev=0`, und `gpu-primary-card` schreibt
`AQ_DRM_DEVICES` zusätzlich in die uwsm-Env-Datei `env-hyprland`, die uwsm
garantiert liest. Beides hält den Hybridbetrieb (nvidia bleibt für hashcat
geladen). Auf der Zielhardware noch nicht bestätigt.

## Was ungetestet blieb

NVIDIA-Modul laden, CUDA und hashcat auf der 4060, `hp-wmi`-Bindung samt
Lüftersteuerung und `platform_profile`, PRIME-Offload und D3cold — dafür
braucht es die echte Hardware, QEMU hat weder NVIDIA-GPU noch HP-Board.

Die Calamares-Installation auf eine Platte habe ich nicht durchgespielt, und
`virtualbox-host-dkms` baut erst beim ersten `postinstall-8845hs`.

Auch der Fix am primären DRM-Gerät ist bislang nur hergeleitet, nicht am Gerät
bestätigt: dass `AQ_DRM_DEVICES` gesetzt ist, lässt sich prüfen — dass damit
alle Boots durchlaufen, zeigt erst eine Reihe von Neustarts.
