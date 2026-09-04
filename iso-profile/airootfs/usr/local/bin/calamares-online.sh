#!/usr/bin/env bash
# Der Online-Installer ist auf dieser ISO absichtlich stillgelegt.
#
# cachyos-hello ruft diesen Pfad fest verdrahtet auf. Der Original-Pfad zieht
# Pakete frisch aus dem Netz und zeigt eine Desktop-Auswahl - dabei ginge
# genau das verloren, was diese ISO ausmacht: linux-leon, der GPU-Offload,
# der Security-Stack. Siehe docs/security-fixes.md.
#
# Deshalb zeigt dieser Shim auf den Offline-Installer.
exec /usr/local/bin/cachy-install "$@"
