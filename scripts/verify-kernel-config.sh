#!/usr/bin/env bash
# Prueft, ob im gebauten Kernel wirklich drinsteht, was wir wollten.
# Notwendig, weil "make oldconfig" bei neuen Symbolen still auf Defaults
# zurueckfallen kann.
# Nutzung: ./scripts/verify-kernel-config.sh <pfad/zur/.config>
set -uo pipefail
C="${1:-}"
[ -r "$C" ] || { echo "Nutzung: $0 <.config>"; exit 1; }
OK=0; BAD=0
chk(){ # chk <symbol> <erwartet: y|m|n|wert> <begruendung>
  local sym="$1" want="$2" why="$3" have
  if grep -q "^CONFIG_${sym}=" "$C"; then have="$(grep -m1 "^CONFIG_${sym}=" "$C" | cut -d= -f2)"
  elif grep -q "^# CONFIG_${sym} is not set" "$C"; then have="n"
  else have="ABWESEND"; fi
  if [ "$have" = "$want" ]; then printf '  \033[32mok\033[0m   %-34s = %-8s %s\n' "$sym" "$have" "$why"; OK=$((OK+1))
  else printf '  \033[31mFALSCH\033[0m %-32s = %-8s (erwartet %s) %s\n' "$sym" "$have" "$want" "$why"; BAD=$((BAD+1)); fi
}
echo "=== Scheduler / Latenz ==="
chk SCHED_BORE                 y   "BORE: Compile-Durchsatz + Responsiveness"
chk PREEMPT_DYNAMIC            y   "zur Laufzeit umschaltbar"
chk DEBUG_FS                   y   "traegt /sys/kernel/debug/sched/preempt"
# CONFIG_SCHED_DEBUG gibt es seit Kernel 7.x nicht mehr - die sched-debugfs-
# Dateien werden in kernel/sched/debug.c unbedingt angelegt, nur DEBUG_FS zaehlt.
chk HZ                      1000   "Tickrate"
chk NO_HZ_IDLE                 y   "tickless idle -> Akku"
chk NO_HZ_FULL                 n   "bewusst AUS (Overhead ohne Nutzen)"
echo "=== Optimierung ==="
chk MZEN4                      y   "-march=znver4"
chk GENERIC_CPU                n   "keine generische CPU"
chk LTO_CLANG_THIN             y   "ThinLTO"
chk CC_OPTIMIZE_FOR_PERFORMANCE_O3 y "-O3"
chk TRANSPARENT_HUGEPAGE_MADVISE   y "madvise statt always -> Akku"
echo "=== Hashcat / GPU ==="
chk HSA_AMD                    y   "ROCm auf der 780M"
chk HSA_AMD_SVM                y   "Shared Virtual Memory"
chk DRM_AMDGPU                 y   "780M"
echo "=== Security / Dev ==="
chk BPF_SYSCALL                y   "eBPF"
chk BPF_JIT_ALWAYS_ON          y   "eBPF JIT"
chk DEBUG_INFO_BTF             y   "BTF fuer CO-RE/bpftrace"
chk BPF_LSM                    y   "BPF-LSM"
chk SECURITY_LANDLOCK          y   "Landlock"
chk SECURITY_YAMA              y   "Yama ptrace_scope"
chk SECURITY_APPARMOR          y   "AppArmor (Docker)"
chk KPROBES                    y   "kprobes"
chk UPROBES                    y   "uprobes"
chk FUNCTION_TRACER            y   "ftrace"
chk KALLSYMS_ALL               y   "vollstaendige Symbole"
chk SLAB_FREELIST_HARDENED     y   "Heap-Haertung"
chk RANDOMIZE_KSTACK_OFFSET    y   "Kernel-Stack-Randomisierung"
chk INIT_ON_ALLOC_DEFAULT_ON   y   "Speicher bei alloc nullen"
chk INIT_ON_FREE_DEFAULT_ON    n   "bewusst AUS (Performance)"
chk LOCK_DOWN_KERNEL_FORCE_NONE y  "kein erzwungener Lockdown"
echo "=== Thermals / Power ==="
chk AMD_PMC                    m   "s2idle auf Phoenix/Hawk Point"
chk AMD_PMF                    m   "Platform Management Framework"
chk SENSORS_K10TEMP            m   "CPU-Temperatur"
chk X86_AMD_PSTATE             y   "EPP-Governor"
echo "=== Speicher / Netz ==="
chk LRU_GEN                    y   "MGLRU"
chk ZRAM                       y   "zram"
chk TCP_CONG_BBR               y   "BBRv3"
echo
echo "  $OK ok, $BAD abweichend"
[ "$BAD" -eq 0 ] || echo "  -> Abweichungen pruefen: evtl. hat make oldconfig auf Defaults zurueckgesetzt."
exit 0
