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

## Was ungetestet blieb

NVIDIA-Modul laden, CUDA und hashcat auf der 4060, `hp-wmi`-Bindung samt
Lüftersteuerung und `platform_profile`, PRIME-Offload und D3cold — dafür
braucht es die echte Hardware, QEMU hat weder NVIDIA-GPU noch HP-Board.

Die Calamares-Installation auf eine Platte habe ich nicht durchgespielt, und
`virtualbox-host-dkms` baut erst beim ersten `postinstall-8845hs`.
