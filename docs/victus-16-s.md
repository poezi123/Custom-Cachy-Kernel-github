# HP Victus 16-s1902ng

Ryzen 7 8845HS · Radeon 780M · RTX 4060 Laptop · 16,1".

## nbfc brauchst du nicht

Kernel 7.2 kann das Gerät nativ. In `drivers/platform/x86/hp/hp-wmi.c` gibt es
einen eigenen Codepfad für Victus-S-Boards, also die 16-**s**-Serie:

```c
/* DMI Board names of Victus 16-r and Victus 16-s laptops */
static const struct dmi_system_id victus_s_thermal_profile_boards[] = { … }
```

Damit gibt es `platform_profile`, getrennte CPU-/GPU-Lüfterdrehzahlen über
hwmon und manuelles `pwm1`. `nbfc-linux` wäre ein Rückschritt: es spricht den EC
direkt an, braucht ein reverse-engineertes Modellprofil und kollidiert mit dem
Treiber.

## Der Zusammenhang mit Hashcat

Im Profil `performance` schaltet der Treiber zusätzlich **CTGP** (Configurable
TGP) und **PPAB** (Dynamic Boost) der 4060 frei — mehr Leistungsbudget für die
GPU. Im Balanced-Profil bleibt das aus.

Deshalb steht `hashcat` in `/etc/gpu-offload.d/apps.list` mit dem Zusatz
`!perf`. Der Shim startet dann:

```sh
powerprofilesctl launch -p performance -- /usr/bin/hashcat "$@"
```

Das Profil gilt nur für die Laufzeit und fällt danach zurück — kein dauerhafter
Akku- und Temperaturnachteil. `powerprofilesctl` braucht dank polkit kein `sudo`.

## Bedienung

```bash
victus status              # Board-ID, Profil, Lüfter, Temperaturen
sudo victus perf           # Performance (CTGP/PPAB an)
sudo victus quiet
sudo victus fan max        # oder: fan 180  /  fan auto
victus diagnose            # falls das Board nicht erkannt wird
```

## Falls die Board-ID fehlt

Welche `DMI_BOARD_NAME` das Gerät meldet, steht erst am Laptop fest. Die
Kernel-Liste kennt 21 IDs (`8902`, `8A44`, `8A4D`, `8BAB`, `8B2F`, `8BBE`,
`8BC2`, `8BCA`, `8BCD`, `8BD4`, `8BD5`, `8C76`–`8C78`, `8C99`, `8C9C`, `8D26`,
`8D41`, `8D87`, `8E35`).

Ist die eigene nicht dabei, legt `hp-wmi` kein `platform_profile` an.
`victus diagnose` erkennt das und gibt den fertigen Codeblock aus — weil wir den
Kernel selbst bauen, ist das ein Einzeiler in `prepare()` plus Rebuild.

Die neueren s-Einträge nutzen `victus_s_thermal_params` (`8C99`, `8C9C`) bzw.
`omen_v1_thermal_params` (`8C76`–`8C78`). Falls Profile zwar schalten, aber
nichts bewirken, ist die jeweils andere Variante die richtige. Wenn es läuft:
an `platform-driver-x86@vger.kernel.org` melden, dann landet die ID upstream.

## Offene Punkte

`ryzenadj` für CPU-TDP-Limits gibt es nur im AUR (`paru -S ryzenadj`). Es
funktioniert auf Hawk Point, kollidiert aber mit den hp-wmi-Profilen — nutz
eins von beidem.

Das Victus 16-s hat keinen MUX-Switch. Die 780M bleibt immer am Display, die
4060 läuft ausschließlich über PRIME-Offload. Genau darauf ist das GPU-Setup
ausgelegt.
