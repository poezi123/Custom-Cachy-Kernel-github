# Verifikation — was tatsächlich gemessen wurde

Alles hier ist **gemessen**, nicht angenommen. Build-Host: Ryzen 5 3600 (Zen 2),
Test in QEMU/KVM mit OVMF.

## Kernel-Config: 37 von 37

`scripts/verify-kernel-config.sh` gegen die `.config` aus dem gebauten
`linux-leon-headers`-Paket:

```
37 ok, 0 abweichend
```

Geprüft: BORE, PREEMPT_DYNAMIC, HZ=1000, NO_HZ_IDLE, MZEN4, ThinLTO, -O3,
THP=madvise, HSA_AMD(+SVM), eBPF/BTF/BPF_LSM, Landlock, Yama, AppArmor,
kprobes/uprobes/ftrace, SLAB-Härtung, KSTACK-Randomisierung,
INIT_ON_ALLOC(an)/INIT_ON_FREE(aus), Lockdown nicht erzwungen,
AMD_PMC/AMD_PMF/K10TEMP, amd_pstate, MGLRU, zram, BBR.

## ISO-Inhalt: 30 von 30

`scripts/verify-iso.sh`:

- El-Torito-Bootkatalog, EFI-Verzeichnis
- `vmlinuz-linux-leon` + `initramfs-linux-leon.img`
- LTS-Rettungskernel
- Im squashfs: alle eigenen Skripte und Configs, `hashcat`, `hyprland`,
  `ghidra`, `VirtualBox`, `docker`, `mold`, `ccache`
- `sshd` **nicht** autostart-aktiv (siehe `security-fixes.md`)
- Beide Modulbäume: `7.2.3-1-leon` und `6.18.48-1-cachyos-lts`
- NVIDIA-Module im Kernelpaket: `nvidia.ko`, `nvidia-drm`, `nvidia-uvm`,
  `nvidia-modeset`, `nvidia-peermem`

## Boot-Test

**GUI (KVM):** ISO gebootet → GRUB → Hyprland mit Noctalia-Shell, Top-Bar,
CachyOS-Hello, Terminal per `SUPER+Return`. Screenshots in `work/shots/`.

**Seriell (Direktboot von Kernel + initramfs):**

```
CachyOS 7.2.3-1-leon (ttyS0)
CachyOS login:
```

Null Panics, Oopses oder Invalid-Opcode-Fehler.

### Laufzeitwerte im laufenden System

| Prüfung | Ergebnis |
|---|---|
| `uname -a` | `7.2.3-1-leon #1 SMP PREEMPT_DYNAMIC` |
| `/sys/kernel/debug/sched/preempt` | `(full) lazy` |
| `kernel.sched_bore` | `1` |
| zram | `/dev/zram0 zstd 3.8G`, Priorität 100 |
| `/sys/kernel/security/lsm` | `lockdown,capability,landlock,yama,apparmor,bpf` |
| `/sys/kernel/btf/vmlinux` | vorhanden, 10,8 MB |
| THP | `always [madvise] never` |
| TCP | `bbr` + `fq` |
| `modinfo nvidia` | `610.57.04` |
| `hp_wmi` | im Baum: `.../platform/x86/hp/hp-wmi.ko.zst` |
| yama/perf/kptr/inotify | `1 / 1 / 1 / 524288` — exakt wie konfiguriert |
| `gpu-offload-sync` | erzeugt Shims, `hashcat` mit `[+performance]` |

Der erzeugte hashcat-Shim endet korrekt mit:

```sh
exec powerprofilesctl launch -p performance -- "/usr/bin/hashcat" "$@"
```

## Zwei Korrekturen aus dem Test

### 1. Der znver4-Kernel bootet sehr wohl auf Zen 2

Ursprüngliche Annahme: `-march=znver4` mache den Kernel auf älteren CPUs
unbootbar, deshalb sei nur der LTS-Kernel lokal testbar. **Falsch.**

Der Kernel wird mit `-mno-sse -mno-mmx -mno-avx` übersetzt — `-march=znver4`
wirkt daher nur auf Instruktions-Scheduling und skalare Befehle, und Zen 4
bringt gegenüber Zen 2 keine neuen skalaren Instruktionen mit (AVX-512 ist rein
vektoriell und wird im Kernel nie erzeugt). Der Kernel bootete auf dem Zen-2-Host
mit `-cpu host` fehlerfrei bis zum Login.

Praktische Folge: der echte Zielkernel ist vollständig lokal testbar.
Der LTS-Kernel bleibt trotzdem auf der ISO — als Rückfallebene, falls
`virtualbox-host-dkms` nach einem Update nicht gegen `linux-leon` baut.

### 2. `vm.swappiness` wird per udev gesetzt, nicht per sysctl

`/etc/sysctl.d/99-leon.conf` enthielt `vm.swappiness = 180`, gemessen wurden
aber 150. Ursache:

```
/usr/lib/udev/rules.d/30-zram.rules   (aus cachyos-settings)
ACTION=="change", KERNEL=="zram0", ATTR{initstate}=="1", SYSCTL{vm.swappiness}="150"
```

Diese Regel läuft **nach** `systemd-sysctl` und gewinnt immer. Alle anderen
Werte aus derselben Datei kamen korrekt an — es liegt also nicht an sysctl.

Konsequenz: die wirkungslose Zeile ist aus `99-leon.conf` entfernt, mit
Kommentar auf die udev-Regel. Wer 180 will, legt
`/etc/udev/rules.d/31-zram-swappiness.rules` an (31 sortiert nach 30).

**Hinweis:** Diese Korrektur ist in der Quelle, aber die bereits gebaute ISO
enthält noch die wirkungslose Zeile. Rein kosmetisch — das Verhalten ist in
beiden Fällen identisch (150). Beim nächsten Rebuild verschwindet sie.

## Was hier nicht geprüft werden konnte

| | Warum |
|---|---|
| NVIDIA-Modul lädt / CUDA / hashcat auf der 4060 | QEMU hat keine NVIDIA-GPU. Modul und Version sind vorhanden, das Laden braucht die echte Karte. |
| `hp-wmi` bindet, Lüfter, `platform_profile` | `modprobe hp-wmi` → `No such device`. Erwartet: kein HP-Board in QEMU. |
| PRIME-Offload, D3cold, `gpu-mode` | Braucht die echte Hybrid-Hardware. |
| Calamares-Offline-Installation auf Platte | Nicht durchgeführt — hätte eine zweite VM mit Zieldatenträger gebraucht. |
| `virtualbox-host-dkms` gegen `linux-leon` | Wird beim ersten `postinstall-8845hs` auf dem Laptop gebaut. |
