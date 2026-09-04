#!/usr/bin/env python3
"""Skriptgesteuerter Boot-Test der ISO in QEMU.

Startet QEMU headless mit Monitor-Socket, waehlt im GRUB-Menue einen Eintrag
und macht in Abstaenden Screenshots. Ohne das muesste man interaktiv am
Bildschirm sitzen.

  ./qemu-boot-test.py --entry lts      KVM, Rettungskernel  (schnell)
  ./qemu-boot-test.py --entry leon     TCG + -cpu max       (sehr langsam)
"""
import argparse, os, shutil, socket, subprocess, sys, time

ROOT = os.environ.get("PROJECT_ROOT", os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
WORK = os.path.join(ROOT, "work"); os.makedirs(WORK, exist_ok=True)
SHOTS = os.path.join(WORK, "shots"); os.makedirs(SHOTS, exist_ok=True)
SOCK = os.path.join(WORK, "qemu-mon.sock")

def newest_iso():
    c = [os.path.join(ROOT, "out", f) for f in os.listdir(os.path.join(ROOT, "out")) if f.endswith(".iso")]
    if not c: sys.exit("Keine ISO in out/")
    return max(c, key=os.path.getmtime)

class Monitor:
    def __init__(self, path, timeout=120):
        t0 = time.time()
        while time.time() - t0 < timeout:
            try:
                self.s = socket.socket(socket.AF_UNIX); self.s.connect(path)
                self.s.settimeout(10); time.sleep(0.5); self._drain(); return
            except (FileNotFoundError, ConnectionRefusedError): time.sleep(0.5)
        sys.exit("Monitor-Socket nicht erreichbar")
    def _drain(self):
        try:
            while True:
                if not self.s.recv(65536): break
        except Exception: pass
    def cmd(self, c):
        self.s.sendall((c + "\n").encode()); time.sleep(0.6); self._drain()
    def shot(self, name):
        ppm = os.path.join(SHOTS, name + ".ppm")
        self.cmd("screendump " + ppm)
        for _ in range(20):
            if os.path.exists(ppm) and os.path.getsize(ppm) > 0: break
            time.sleep(0.5)
        png = os.path.join(SHOTS, name + ".png")
        if os.path.exists(ppm):
            subprocess.run(["magick", ppm, png], check=False)
            os.remove(ppm)
            print(f"  Screenshot: {png}", flush=True)
        else:
            print(f"  Screenshot {name} fehlgeschlagen", flush=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--entry", choices=["leon", "lts", "fallback"], default="lts")
    ap.add_argument("--minutes", type=float, default=8.0)
    a = ap.parse_args()

    iso = newest_iso()
    code = next((c for c in ["/usr/share/edk2/x64/OVMF_CODE.4m.fd",
                             "/usr/share/ovmf/x64/OVMF_CODE.4m.fd"] if os.path.exists(c)), None)
    if not code: sys.exit("Keine OVMF-Firmware")
    varsrc = code.replace("CODE", "VARS")
    varf = os.path.join(WORK, "OVMF_VARS.test.fd"); shutil.copyfile(varsrc, varf)
    if os.path.exists(SOCK): os.remove(SOCK)

    args = ["qemu-system-x86_64", "-machine", "q35", "-m", "6G", "-smp", "4",
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,unit=1,file={varf}",
            "-cdrom", iso, "-boot", "d",
            "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
            "-vga", "virtio", "-display", "none",
            "-monitor", f"unix:{SOCK},server,nowait"]
    if a.entry == "leon":
        # Der Host (Zen 2) kann kein AVX-512, linux-leon ist aber znver4.
        # Nur TCG emuliert das - entsprechend langsam.
        args += ["-accel", "tcg", "-cpu", "max"]
    else:
        args += ["-accel", "kvm", "-cpu", "host"]

    print(f">>> ISO:   {os.path.basename(iso)}")
    print(f">>> Modus: {a.entry} ({'TCG' if a.entry=='leon' else 'KVM'})", flush=True)
    qemu = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        mon = Monitor(SOCK)
        time.sleep(12 if a.entry != "leon" else 45)
        mon.shot("01-grub")
        # Menue: 0 = linux-leon, 1 = LTS, 2 = Fallback (dazwischen zwei Trennzeilen)
        downs = {"leon": 0, "lts": 1, "fallback": 2}[a.entry]
        for _ in range(downs):
            mon.cmd("sendkey down"); time.sleep(0.4)
        mon.cmd("sendkey ret")
        print(">>> Eintrag gewaehlt, warte auf Boot ...", flush=True)
        deadline = time.time() + a.minutes * 60
        n = 2
        while time.time() < deadline:
            time.sleep(45)
            mon.shot(f"{n:02d}-boot")
            n += 1
            if qemu.poll() is not None:
                print(">>> QEMU beendet."); break
    finally:
        try: qemu.terminate(); qemu.wait(timeout=10)
        except Exception: qemu.kill()
        if os.path.exists(SOCK): os.remove(SOCK)
    print(">>> Test beendet.")

main()
