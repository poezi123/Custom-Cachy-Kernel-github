# Hyprland

Die Basis ist das offizielle CachyOS-Setup aus den Paketen
`cachyos-hypr-noctalia` + `noctalia-shell`. Deren Dotfiles landen über
`/etc/skel` im Benutzerverzeichnis und werden hier **nicht** dupliziert —
sonst würden sie bei jedem Paket-Update auseinanderlaufen.

Ergänzt wird nur eine Datei, hybrid-spezifisch:

`iso-profile/airootfs/etc/skel/.config/uwsm/env-hyprland`

`uwsm` liest neben `~/.config/uwsm/env` auch `env-<compositor>`. Dadurch bleibt
die CachyOS-Datei unangetastet und beide koexistieren.

## Warum dort keine NVIDIA-Variablen stehen

Die CachyOS-Datei enthält auskommentierte Zeilen wie

```sh
# export GBM_BACKEND=nvidia-drm
# export __GLX_VENDOR_LIBRARY_NAME=nvidia
```

Die sind für Rechner mit **ausschließlich** NVIDIA-GPU gedacht. Auf diesem
Hybrid-Laptop würden sie den kompletten Desktop über die 4060 rendern — die
GPU käme nie in D3cold und der Akkuvorteil wäre weg.

Der Offload läuft stattdessen **pro Programm** über die Shims in
`/usr/local/lib/gpu-offload`, gespeist aus `/etc/gpu-offload.d/apps.list`.
