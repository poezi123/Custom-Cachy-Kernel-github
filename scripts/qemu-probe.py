#!/usr/bin/env python3
"""Bootet die ISO, oeffnet in Hyprland ein Terminal und tippt Befehle hinein.

Ohne das laesst sich von aussen nicht belegen, WELCHER Kernel laeuft und ob
die Laufzeit-Schalter (PREEMPT_DYNAMIC, zram, sysctl) wirklich greifen.
Die Ausgabe wird per QEMU-screendump abfotografiert.
"""
import os, shutil, socket, subprocess, sys, time

ROOT = os.environ.get("PROJECT_ROOT", os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
WORK = os.path.join(ROOT, "work"); SHOTS = os.path.join(WORK, "shots")
os.makedirs(SHOTS, exist_ok=True)
SOCK = os.path.join(WORK, "qemu-probe.sock")

KEYS = {' ': 'spc', '-': 'minus', '_': 'shift-minus', '.': 'dot', '/': 'slash',
        ';': 'semicolon', ':': 'shift-semicolon', '=': 'equal', ',': 'comma',
        "'": 'apostrophe', '"': 'shift-apostrophe', '|': 'shift-backslash',
        '\\': 'backslash', '(': 'shift-9', ')': 'shift-0', '$': 'shift-4',
        '&': 'shift-7', '*': 'shift-8', '>': 'shift-dot', '<': 'shift-comma',
        '!': 'shift-1', '#': 'shift-3', '~': 'shift-grave_accent'}

def keyname(ch):
    if ch in KEYS: return KEYS[ch]
    if ch.isdigit(): return ch
    if ch.isalpha(): return ch.lower() if ch.islower() else 'shift-' + ch.lower()
    return None

class Mon:
    def __init__(self, path, timeout=180):
        t0 = time.time()
        while time.time() - t0 < timeout:
            try:
                self.s = socket.socket(socket.AF_UNIX); self.s.connect(path)
                self.s.settimeout(10); time.sleep(0.5); self.drain(); return
            except (FileNotFoundError, ConnectionRefusedError): time.sleep(0.5)
        sys.exit("Monitor nicht erreichbar")
    def drain(self):
        try:
            while True:
                if not self.s.recv(65536): break
        except Exception: pass
    def cmd(self, c, wait=0.35):
        self.s.sendall((c + "\n").encode()); time.sleep(wait); self.drain()
    def type(self, text):
        for ch in text:
            k = keyname(ch)
            if k: self.cmd("sendkey " + k, 0.06)
    def shot(self, name):
        ppm = os.path.join(SHOTS, name + ".ppm")
        self.cmd("screendump " + ppm, 1.0)
        for _ in range(30):
            if os.path.exists(ppm) and os.path.getsize(ppm) > 0: break
            time.sleep(0.5)
        png = os.path.join(SHOTS, name + ".png")
        if os.path.exists(ppm):
            subprocess.run(["magick", ppm, png], check=False); os.remove(ppm)
            print("  Screenshot:", png, flush=True)

code = next(c for c in ["/usr/share/edk2/x64/OVMF_CODE.4m.fd"] if os.path.exists(c))
varf = os.path.join(WORK, "OVMF_VARS.probe.fd")
shutil.copyfile(code.replace("CODE", "VARS"), varf)
iso = max([os.path.join(ROOT, "out", f) for f in os.listdir(os.path.join(ROOT, "out")) if f.endswith(".iso")],
          key=os.path.getmtime)
if os.path.exists(SOCK): os.remove(SOCK)

qemu = subprocess.Popen(
    ["qemu-system-x86_64", "-machine", "q35", "-m", "6G", "-smp", "4",
     "-accel", "kvm", "-cpu", "host",
     "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
     "-drive", f"if=pflash,format=raw,unit=1,file={varf}",
     "-cdrom", iso, "-boot", "d",
     "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
     "-vga", "virtio", "-display", "none",
     "-monitor", f"unix:{SOCK},server,nowait"],
    stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
print(">>> QEMU gestartet, GRUB bootet den Default-Eintrag (linux-leon).", flush=True)
try:
    mon = Mon(SOCK)
    print(">>> warte auf den Desktop ...", flush=True)
    time.sleep(255)
    mon.shot("p1-desktop")
    mon.cmd("sendkey esc"); time.sleep(1)          # Willkommensdialog schliessen
    mon.cmd("sendkey meta_l-ret"); time.sleep(12)  # Terminal oeffnen
    mon.shot("p2-terminal")
    mon.type("clear; uname -r; echo ---; cat /sys/kernel/debug/sched/preempt")
    mon.cmd("sendkey ret"); time.sleep(6)
    mon.shot("p3-uname")
    mon.type("clear; zramctl; sysctl -n vm.swappiness kernel.yama.ptrace_scope kernel.perf_event_paranoid")
    mon.cmd("sendkey ret"); time.sleep(6)
    mon.shot("p4-sysctl")
    mon.type("clear; ls /usr/local/bin/ | head -20; echo ---; cat /var/lib/gpu-mode")
    mon.cmd("sendkey ret"); time.sleep(6)
    mon.shot("p5-tools")
finally:
    try: qemu.terminate(); qemu.wait(timeout=10)
    except Exception: qemu.kill()
    if os.path.exists(SOCK): os.remove(SOCK)
print(">>> fertig.")
