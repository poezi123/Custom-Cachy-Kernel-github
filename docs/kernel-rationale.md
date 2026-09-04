# Warum der Kernel so gebaut ist

Basis: [linux-cachyos](https://github.com/CachyOS/linux-cachyos) 7.2.3, eigener
`pkgbase` (`linux-leon`) damit Repo-Updates nichts überschreiben.

Prioritäten waren Compile-Speed und Hashcat ganz oben, dann Akku,
Responsiveness, Security/Dev, Thermik. Gaming egal. Da stecken echte
Zielkonflikte drin — hier steht, wie ich sie aufgelöst habe.

## Die Entscheidungen, die weh taten

**BORE als Scheduler.** Compile-Durchsatz und Responsiveness ziehen
gegeneinander: was Durchsatz maximiert, lässt lange Zeitscheiben laufen und
macht den Desktop zäh. BORE gewichtet interaktive Tasks nach ihrem
Burst-Verhalten und lässt Batch-Last dazwischen durchlaufen. Unter `make -j16`
bleibt der Desktop bedienbar.

**`PREEMPT_DYNAMIC`.** Zur Laufzeit umschaltbar — `full` im Alltag, `lazy` für
lange Builds. Genau diese zwei Modi gibt es; seit Kernel 6.13 ersetzt
`PREEMPT_LAZY` das alte `voluntary`.

```bash
echo lazy | sudo tee /sys/kernel/debug/sched/preempt
```

**`NO_HZ_IDLE` statt CachyOS' `NO_HZ_FULL`.** Full-Tickless kostet Overhead pro
Context-Switch und nützt nur bei CPU-Isolation im HPC-Umfeld. Auf einem Laptop
ist `idle` sparsamer *und* schneller.

**THP `madvise` statt `always`.** `always` plus khugepaged bläht den Speicher
auf und erzeugt Wakeups. Wer Hugepages will, fordert sie per `madvise()` an.

**NVIDIA-Open im Kernelpaket statt in DKMS.** Der wichtigste Punkt für Hashcat:
so kann ein Kernel-Update keinen Versionskonflikt zwischen Modul und Kernel
erzeugen — der klassische Weg, auf dem CUDA nach einem Update stirbt.

**Kein kCFI.** Kostet 2–3 %, und das NVIDIA-Modul würde mitkompiliert. Bei
Compile und Hashcat als Top-Prioritäten der falsche Tausch. Nachrüstbar.

**Kein `_localmodcfg`.** Würde nur Module bauen, die der *Build-Host* geladen
hat — eine andere Maschine als das Ziel. Das nähme dem Laptop Treiber weg.

## Der Rest

`-march=znver4`, Clang ThinLTO (nicht `full`, das linkt einthreadig und braucht
>16 GB), `-O3`, 1000 Hz, kein Performance-Governor, BBRv3 mit `fq`, MGLRU,
zram/zstd.

Der eigene Config-Block in `prepare()` (`### LEON:`) ergänzt: moderate Härtung
(Landlock, Yama, AppArmor, BPF-LSM, SLAB-Härtung, KSTACK-Randomisierung,
`INIT_ON_ALLOC`), volles eBPF mit BTF, kprobes/uprobes/ftrace, KVM-AMD,
VFIO+IOMMUFD, `AMD_PMC`/`AMD_PMF` für s2idle und Thermik, `HSA_AMD` für ROCm
auf der 780M, und die Plattformtreiber für HP/Acer/MSI als Modul.

Lockdown ist gebaut, aber **nicht erzwungen** — sonst wären eBPF-Tracing,
`/dev/mem` und das NVIDIA-Modul blockiert. `INIT_ON_FREE` ist aus (spürbare
Kosten), per `init_on_free=1` beim Booten zuschaltbar.

## Abweichung: BTF nur für vmlinux

`DEBUG_INFO_BTF_MODULES` ist aus, obwohl CachyOS es anhat — `pahole` 1.31
bricht beim NVIDIA-Modul ab (`btf permute: Invalid argument`), und zwar erst
nach 55 Minuten, wenn alles andere längst steht.

vmlinux-BTF bleibt an, bpftrace und CO-RE gegen Kernelstrukturen funktionieren
also. Verloren geht nur CO-RE gegen Typen, die es nur in Modulen gibt.
Randfall gegen "hashcat läuft überhaupt". Sobald pahole gefixt ist:
`scripts/config -d DEBUG_INFO_BTF_MODULES` aus `prepare()` entfernen.

## Zwei Dinge zum Mitnehmen

Der Kernel ist auf Zen 4 optimiert, bootet aber auch auf älteren CPUs — er wird
mit `-mno-sse -mno-avx` übersetzt, `-march=znver4` wirkt also nur auf Scheduling
und skalare Befehle. Der LTS-Kernel liegt trotzdem mit auf der ISO, falls
`virtualbox-host-dkms` mal nicht gegen `linux-leon` baut.

CPU-Mitigations sind vollständig aktiv. Bewusst, kostet beim Kompilieren 2–5 %.
