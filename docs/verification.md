# Was getestet wurde

Gebaut auf einem Ryzen 5 3600 (Zen 2), geprüft in QEMU/KVM und danach auf dem
echten Victus (Live-Sitzung über SSH).

## Automatische Prüfungen

`scripts/verify-kernel-config.sh` gegen die `.config` aus dem Headers-Paket:
**37/37** — BORE, PREEMPT_DYNAMIC, HZ 1000, MZEN4, ThinLTO, THP madvise,
HSA_AMD, eBPF/BTF, alle LSMs, Härtung, AMD_PMC/PMF, amd_pstate, MGLRU, zram, BBR.
`DRM_AMDGPU` wird als Modul (`=m`) erwartet.

`scripts/verify-iso.sh`: **30/30** — Bootkatalog, EFI, beide Kernel, und im
squashfs die eigenen Skripte plus hashcat, hyprland, ghidra, VirtualBox, docker.
Und dass `sshd` nicht autostart-aktiv ist.

## Laufzeitwerte (echte Hardware)

| | |
|---|---|
| `uname` | `7.2.3-1-leon`, PREEMPT_DYNAMIC |
| `sched/preempt` | `(full) lazy` |
| `kernel.sched_bore` | `1` |
| LSM-Kette | `lockdown,capability,landlock,yama,apparmor,bpf` |
| BTF / THP / TCP / zram / MGLRU | da / madvise / bbr+fq / zstd 16G / an |
| yama/perf/kptr/inotify | `1 / 1 / 1 / 524288` |
| NVIDIA 4060 | Treiber 610.57.04, 8 GB, CUDA 13.3 in hashcat |
| amdgpu 780M | treibt eDP-1 @144 Hz |
| hp-wmi Victus `8C9C` | nativ: platform_profile (3 Modi), Lüfter-RPM, BIOS F.15 |

Damit ist die offene Frage aus `victus-16-s.md` beantwortet: **8C9C wird nativ
unterstützt**, kein nbfc nötig.

## Auf echter Hardware gefunden und gefixt

- **Schwarzer Schirm.** amdgpu (780M) lud gar nicht — das PKGBUILD baute es als
  builtin (`-e DRM_AMDGPU`), builtin startet vor dem Wurzel-FS und findet seine
  Firmware nicht. Fix: als Modul bauen (`-m`). Dazu muss `AQ_DRM_DEVICES` auf
  den echten Node `/dev/dri/cardN` zeigen (nicht den by-path-Symlink), sonst
  stürzt Hyprland mit `CBackend::create() failed!` ab. Beides erledigt
  `gpu-primary.service`.
- **Installer startete nicht** (`Testing-ISO`): `/etc/version-tag` fehlte,
  `build-iso.sh` schreibt es jetzt.
- **Calamares stürzte ab** (boost-Soname): calamares-next ist gegen boost 1.91
  gelinkt, das Repo liefert 1.92 — die 1.91-Libs werden beigelegt.
- **Kein Bootloader nach Installation**: Calamares wollte limine (Paket-Default,
  nicht installiert); ein Override erzwingt grub.

## Zwei Annahmen, die falsch waren

**Der znver4-Kernel bootet auf Zen 2.** Er wird mit `-mno-sse -mno-mmx -mno-avx`
übersetzt, `-march` wirkt nur auf Scheduling und skalare Befehle. Der echte
Zielkernel ist also lokal testbar.

**`vm.swappiness` kommt per udev, nicht per sysctl.** `30-zram.rules` aus
cachyos-settings setzt `150` nach `systemd-sysctl` und gewinnt immer. Die
wirkungslose Zeile aus `99-leon.conf` ist raus.

## Bekannte Lücke: 780M ohne OpenCL

`clinfo` zeigt nur die NVIDIA-CUDA-Plattform. Der Kernel kann ROCm (HSA_AMD),
aber der Userspace fehlt (`rocm-opencl-runtime`). Bewusst nicht nachgezogen: die
780M (gfx1103) ist von ROCm nicht offiziell unterstützt, und gegenüber der 4060
lohnt es für hashcat nicht. hashcat läuft auf der 4060.

## Ungetestet

Die Calamares-Installation auf eine echte Platte samt erstem Boot des
installierten Systems, PRIME-Offload und D3cold unter Last, und ob
`virtualbox-host-dkms` beim ersten `postinstall-8845hs` durchbaut.
