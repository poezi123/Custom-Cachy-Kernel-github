#!/usr/bin/env bash
# Baut linux-leon im Container. Optionswahl siehe docs/kernel-rationale.md
#
# ccache wird per PATH-Masquerading eingehaengt (/usr/lib/ccache/bin liegt vor
# /usr/bin, "clang" dort ist ein Symlink auf ccache). Das funktioniert
# transparent mit LLVM=1, ohne CC= in die make-Flags zu fummeln. Ein zweiter
# Durchlauf nach einem spaeten Fehlschlag kostet dadurch Minuten statt einer Stunde.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PROJECT_ROOT:-$(dirname "$REPO")}"
mkdir -p "$ROOT/cache/src" "$ROOT/cache/ccache" "$ROOT/out"

docker run --rm -i --name linux-leon-build \
  -v "$ROOT/build/linux-leon:/build/pkg:ro" \
  -v "$ROOT/out:/out" \
  -v "$ROOT/cache/src:/srcdest" \
  -v "$ROOT/cache/ccache:/ccache" \
  -e CCACHE_DIR=/ccache \
  -e CCACHE_MAXSIZE=20G \
  -e CCACHE_SLOPPINESS=locale,time_macros,include_file_mtime,include_file_ctime \
  -e _cachy_config=yes -e _cpusched=bore -e _HZ_ticks=1000 -e _tickrate=idle \
  -e _preempt=full -e _hugepage=madvise -e _processor_opt=zen4 \
  -e _use_llvm_lto=thin -e _cc_harder=yes -e _tcp_bbr3=yes -e _per_gov=no \
  -e _use_kcfi=no -e _build_nvidia_open=yes -e _build_zfs=no \
  -e _build_debug=no -e _localmodcfg=no \
  -e MAKEFLAGS="-j10" \
  cachy-builder:v2 bash -euo pipefail -c '
    echo ">>> GPG-Keys der CachyOS-Kernel-Maintainer importieren"
    for K in E18447AC260021D31F3FF6C4C8A2A4774B8B63C4 E8B9AA39F054E30E8290D492C3C4820857F654FE; do
      gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$K" 2>/dev/null \
        || gpg --batch --keyserver keys.openpgp.org --recv-keys "$K" 2>/dev/null \
        || echo "WARN: Key $K nicht importierbar"
    done

    sudo sed -i "s|^#\?SRCDEST=.*|SRCDEST=/srcdest|" /etc/makepkg.conf
    sudo chown builder /srcdest /ccache

    export PATH="/usr/lib/ccache/bin:$PATH"
    ccache -M "$CCACHE_MAXSIZE" >/dev/null
    ccache -z >/dev/null
    echo ">>> ccache aktiv: $(command -v clang)"

    cp -r /build/pkg /home/builder/work && cd /home/builder/work
    echo ">>> makepkg startet ($(nproc) Kerne)"
    makepkg -s --noconfirm --needed

    echo ">>> ccache-Statistik:"; ccache -s | head -8
    ls -lh ./*.pkg.tar.zst && cp -v ./*.pkg.tar.zst /out/
  '
