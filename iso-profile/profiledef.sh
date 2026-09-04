#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="cachyos-8845hs"
iso_label="COS8845_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Leon - based on CachyOS <https://cachyos.org>"
iso_application="CachyOS 8845HS - Hyprland / Security / Compute"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
## GRUB
bootmodes=('bios.syslinux' 'uefi.grub')
## systemd-boot
#bootmodes=('bios.syslinux' 'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd -19 statt xz: ~3x schnelleres Packen bei ~5% groesserer ISO.
# Entpackt beim Booten und beim Offline-Install deutlich schneller.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/etc/polkit-1/rules.d"]="0:0:750"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/dmcheck"]="0:0:755"
  ["/usr/local/bin/calamares-online.sh"]="0:0:755"
  ["/usr/local/bin/remove-nvidia"]="0:0:755"
  ["/usr/local/bin/removeun"]="0:0:755"
  ["/usr/local/bin/removeun-online"]="0:0:755"
  ["/usr/local/bin/prepare-live-desktop.sh"]="0:0:755"
  ["/usr/local/bin/cachy-install"]="0:0:755"
  ["/usr/local/bin/switch-to-v4"]="0:0:755"
  ["/usr/local/bin/postinstall-8845hs"]="0:0:755"
  ["/usr/local/bin/victus"]="0:0:755"
  ["/usr/local/bin/gpu-mode"]="0:0:755"
  ["/usr/local/bin/gpu-primary-card"]="0:0:755"
  ["/usr/local/bin/gpu-offload-sync"]="0:0:755"
  ["/usr/local/bin/pkexec-wrapper"]="0:0:755"
)
