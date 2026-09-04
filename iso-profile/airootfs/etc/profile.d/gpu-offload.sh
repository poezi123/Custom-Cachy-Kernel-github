# shellcheck shell=sh
# Shim-Verzeichnis fuer automatischen dGPU-Offload vor /usr/bin haengen.
case ":$PATH:" in
  *":/usr/local/lib/gpu-offload:"*) ;;
  *) PATH="/usr/local/lib/gpu-offload:$PATH"; export PATH ;;
esac
