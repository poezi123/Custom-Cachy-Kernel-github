#!/usr/bin/env bash
# cachyos-hello ruft diesen Pfad fest verdrahtet auf - wir leiten auf den Offline-Installer um.
exec /usr/local/bin/cachy-install "$@"
