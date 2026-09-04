FROM archlinux:base-devel

RUN pacman -Syu --noconfirm --needed wget curl git sudo gawk python

# --- CachyOS-Repos deterministisch einrichten -------------------------------
# Bewusst KEIN "|| true": scheitert das Repo-Setup, soll der Image-Build scheitern.
RUN set -eux; \
    M="https://mirror.cachyos.org/repo/x86_64/cachyos"; \
    sed 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf > /tmp/nosig.conf; \
    for P in cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do \
      F="$(curl -s "$M/" | grep -oE "${P}-[0-9][^\"<]*\.pkg\.tar\.zst" | sort -V | tail -1)"; \
      test -n "$F"; \
      curl -fsSL -o "/tmp/$F" "$M/$F"; \
      pacman -U --noconfirm --config /tmp/nosig.conf "/tmp/$F"; \
    done; \
    pacman-key --init; \
    pacman-key --populate cachyos

# v3-Repos VOR [core] einhaengen (Reihenfolge in pacman.conf = Prioritaet).
# v3 statt v4, weil der Build-Host (Zen 2) kein AVX-512 kann und mkarchiso
# Binaries aus dem airootfs im chroot ausfuehrt. Auf v4 wird post-install
# umgestellt: scripts/switch-to-v4.sh
RUN set -eux; \
    printf '%s\n' \
      '[cachyos-v3]'       'Include = /etc/pacman.d/cachyos-v3-mirrorlist' '' \
      '[cachyos-core-v3]'  'Include = /etc/pacman.d/cachyos-v3-mirrorlist' '' \
      '[cachyos-extra-v3]' 'Include = /etc/pacman.d/cachyos-v3-mirrorlist' '' \
      '[cachyos]'          'Include = /etc/pacman.d/cachyos-mirrorlist'    '' \
      > /tmp/cachy.repos; \
    sed -i 's/^Architecture *=.*/Architecture = x86_64 x86_64_v3/' /etc/pacman.conf; \
    gawk '/^\[core\]/ && !d {while ((getline l < "/tmp/cachy.repos") > 0) print l; d=1} {print}' \
      /etc/pacman.conf > /tmp/pacman.conf.new; \
    mv /tmp/pacman.conf.new /etc/pacman.conf; \
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf; \
    grep -E '^\[' /etc/pacman.conf; \
    pacman -Syu --noconfirm

# Hinweis: kein explizites "zlib" - CachyOS liefert zlib-ng-compat, das zlib
# bereitstellt und mit ihm kollidiert. makepkg erkennt das ueber provides.
# --- Kernel-Build ------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
      bc binutils cpio gettext glibc libelf libgcc openssl pahole perl \
      python rust rust-bindgen rust-src tar xxhash xz zstd \
      clang llvm lld ccache cmake ninja

# --- ISO-Build ---------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
      archiso mkinitcpio-archiso squashfs-tools grub edk2-shell \
      dosfstools libisoburn erofs-utils

RUN useradd -m -u 1000 -G wheel builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder

USER builder
WORKDIR /build
