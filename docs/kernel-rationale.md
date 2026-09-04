# linux-leon — warum welche Option

Zielhardware: **AMD Ryzen 7 8845HS** (Zen 4, "Hawk Point", 8C/16T)
+ **Radeon 780M** (RDNA3, gfx1103) + **NVIDIA RTX 4060 Laptop** (Ada, AD107).

Basis: [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos), Kernel 7.2.3.
Eigener `pkgbase` (`linux-leon`), damit Repo-Updates das Paket nicht überschreiben.

## Priorisierung

| Anforderung | Gewicht |
|---|---|
| Compile Speed | 10 |
| Hashcat | 10 |
| Battery | 9 |
| Responsiveness | 9 |
| Security/Dev | 9 |
| Thermals/Fans | 9 |
| Gaming | 1 |

Die Liste enthält echte Zielkonflikte. Die interessanten sind unten begründet.

## Optionen

| Option | Wert | Begründung |
|---|---|---|
| `_cpusched` | `bore` | **Der zentrale Kompromiss.** Compile-Durchsatz (10) und Responsiveness (9) ziehen normalerweise gegeneinander: ein Scheduler, der Durchsatz maximiert, lässt lange Zeitscheiben laufen und macht den Desktop zäh. BORE gewichtet interaktive Tasks nach ihrem "Burst"-Verhalten und lässt Batch-Last dazwischen voll durchlaufen. Unter `make -j16` bleibt der Desktop bedienbar. |
| `_preempt` | `full` | Gebaut als `PREEMPT_DYNAMIC` → zur Laufzeit umschaltbar. Im laufenden Kernel gemessen: `cat /sys/kernel/debug/sched/preempt` → `(full) lazy`. Die verfügbaren Modi sind **full** und **lazy**, nicht `none`/`voluntary` — seit Kernel 6.13 ersetzt `PREEMPT_LAZY` diese im dynamischen Satz eines PREEMPT-Builds. Alltag `full` (Latenz), für lange Builds `lazy` (verschiebt das Verdrängen von SCHED_OTHER-Tasks auf den nächsten Tick → mehr Durchsatz): `echo lazy \| sudo tee /sys/kernel/debug/sched/preempt`. `CONFIG_SCHED_DEBUG` gibt es seit Kernel 7.x nicht mehr; die Datei hängt nur noch an `DEBUG_FS` (=y). |
| `_tickrate` | `idle` | Abweichung vom CachyOS-Default `full`. `NO_HZ_FULL` kostet Overhead pro Context-Switch und nützt nur bei CPU-Isolation (HPC). Auf einem Laptop ist `idle` sowohl sparsamer als auch schneller. |
| `_HZ_ticks` | `1000` | Responsiveness. Zusammen mit `NO_HZ_IDLE` kostet das im Leerlauf praktisch nichts, weil dort gar keine Ticks feuern. |
| `_processor_opt` | `zen4` | `-march=znver4`. **Wichtig:** dieser Kernel bootet dadurch *nicht* auf älteren CPUs. Deshalb liegt `linux-cachyos-lts` als generischer Rettungskernel mit auf der ISO. |
| `_use_llvm_lto` | `thin` | Clang ThinLTO. `full` linkt einthreadig und braucht >16 GB — auf dem Build-Host (15 GB) nicht machbar. |
| `_hugepage` | `madvise` | Abweichung vom Default `always`. `always` + khugepaged bläht den Speicher auf und erzeugt Wakeups → schlecht für Akku (9). Programme, die THP wollen, fordern es per `madvise()` an. |
| `_per_gov` | `no` | Kein Performance-Governor als Default. `amd_pstate` im EPP-Modus darf takten, wie es Akku (9) und Thermals (9) verlangen. |
| `_build_nvidia_open` | `yes` | **Der wichtigste Punkt für Hashcat (10).** Das NVIDIA-Open-Modul wird in das Kernelpaket kompiliert statt per DKMS gebaut. Ein Kernel-Update kann damit keinen Versionskonflikt zwischen Modul und Kernel erzeugen — der klassische Weg, auf dem CUDA nach einem Update stirbt. |
| `_cc_harder` | `yes` | `-O3`. |
| `_tcp_bbr3` | `yes` | BBRv3 als Default-Congestion-Control, dazu `fq` als qdisc. |
| `_use_kcfi` | `no` | kCFI kostet 2–3 % und das NVIDIA-Modul würde mitkompiliert. Bei Compile (10) und Hashcat (10) als Top-Prioritäten ist das der falsche Tausch. Nachrüstbar. |
| `_localmodcfg` | `no` | Würde nur Module bauen, die der **Build-Host** geladen hat. Wir bauen auf anderer Hardware als der Zielhardware — das würde dem Laptop Treiber wegnehmen. |

## Eigener Config-Block

Über die PKGBUILD-Optionen hinaus setzt `prepare()` einen zusätzlichen Block
(im PKGBUILD als `### LEON:` markiert):

- **Härtung, moderat:** Landlock, Yama, AppArmor, BPF-LSM, `SLAB_FREELIST_HARDENED`,
  `RANDOMIZE_KSTACK_OFFSET`, `HARDENED_USERCOPY`, `INIT_ON_ALLOC_DEFAULT_ON`.
  Lockdown ist eingebaut, aber **nicht erzwungen** (`LOCK_DOWN_KERNEL_FORCE_NONE`) —
  sonst wären eBPF-Tracing, `/dev/mem` und das NVIDIA-Modul blockiert.
  `INIT_ON_FREE_DEFAULT_ON` ist bewusst **aus** (spürbare Kosten); bei Bedarf
  per Bootparameter `init_on_free=1` zuschaltbar.
- **Security-/Dev-Arbeit:** volles eBPF (`BPF_JIT_ALWAYS_ON`, BTF inkl. Module),
  kprobes/uprobes/fprobe, ftrace, `PERF_EVENTS`, `KALLSYMS_ALL`, KVM-AMD mit SEV,
  VFIO + IOMMUFD, `USB_DUMMY_HCD` (USB-Geräte-Emulation ohne echte UDC-Hardware).
- **Thermals/Power:** `AMD_PMC` (s2idle), `AMD_PMF` (Platform Management Framework —
  auf Phoenix/Hawk-Point für Lüfter- und TDP-Steuerung zuständig), `K10TEMP`,
  `NCT6775`/`NCT6683` (Super-I/O-Sensoren, die viele Laptop-Lüftertools brauchen).
- **Plattformtreiber HP/Acer/MSI:** alle als Modul. Ein ungenutztes Modul kostet
  nichts; das exakte Laptop-Modell stand beim Bau noch nicht fest.
- **780M:** `HSA_AMD` + `HSA_AMD_SVM` → ROCm/HIP ist auf der iGPU nutzbar.
- **Speicher:** MGLRU aktiv, zram mit zstd, `zswap` deaktiviert (beides zusammen
  ist Unsinn).

## Abweichung: BTF nur für vmlinux, nicht für Module

`CONFIG_DEBUG_INFO_BTF_MODULES` ist **deaktiviert** — CachyOS hat es per Default an.

Grund: `pahole` 1.31 bricht beim Erzeugen der BTF-Daten für die NVIDIA-Open-Module ab:

```
BTF [M] nvidia-peermem.ko
FAILED: btf permute: Invalid argument
FAILED to sort BTF: Invalid argument
make[5]: *** [scripts/Makefile.modfinal:52: nvidia-peermem.ko] Error 255
```

Das killt den kompletten Build, und zwar erst nach ~55 Minuten, wenn Kernel und
alle Module längst fertig sind.

`CONFIG_DEBUG_INFO_BTF` (vmlinux) bleibt aktiv. Praktische Auswirkung:

| | |
|---|---|
| bpftrace, libbpf, BCC gegen Kernelstrukturen | funktioniert |
| CO-RE gegen vmlinux-Typen | funktioniert |
| `bpftool btf dump file /sys/kernel/btf/vmlinux` | funktioniert |
| CO-RE gegen Typen, die **nur** in einem Modul definiert sind | fehlt |

Der letzte Punkt ist ein Randfall. Gegen die 10/10-Priorität Hashcat — die ohne
das NVIDIA-Modul gar nicht erfüllbar wäre — ist das ein eindeutiger Tausch.

Rückgängig zu machen, sobald pahole den Bug behoben hat: die Zeile
`scripts/config -d DEBUG_INFO_BTF_MODULES` in `prepare()` entfernen.

## Bekannte Konsequenzen

1. **Der Kernel bootet nur auf Zen 4 oder neuer.** Gewollt (znver4), abgesichert
   durch den LTS-Rettungskernel im GRUB-Menü.
2. **VirtualBox bleibt der wackligste Baustein.** `virtualbox-host-dkms` muss bei
   jedem Kernel-Update gegen Clang/LTO neu bauen. CachyOS' `dkms-clang.patch` ist
   drin, aber ein Upstream-Bruch ist jederzeit möglich → dann LTS booten.
3. **CPU-Mitigations sind vollständig aktiv.** Bewusste Entscheidung, kostet bei
   Compile-Workloads ~2–5 %.
