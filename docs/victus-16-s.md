# HP Victus 16-s1902ng

Ryzen 7 8845HS (Zen 4) · Radeon 780M · RTX 4060 Laptop · 16,1".

## Kurzfassung: nbfc-linux wird nicht gebraucht

Der Kernel kann das Gerät nativ. In `drivers/platform/x86/hp/hp-wmi.c` (Kernel 7.2)
gibt es eine eigene Codepfad-Familie für **Victus-S-Boards** — also die
16-**s**-Serie:

```c
/* DMI Board names of Victus 16-r and Victus 16-s laptops */
static const struct dmi_system_id victus_s_thermal_profile_boards[] __initconst = { … }
```

Damit stehen zur Verfügung:

| Fähigkeit | Interface |
|---|---|
| Thermik-Profile | `/sys/firmware/acpi/platform_profile` (`performance` / `balanced` / `low-power`) |
| Lüfterdrehzahlen lesen | hwmon `fan1_input`, `fan2_input` (CPU- und GPU-Lüfter getrennt) |
| Lüfter manuell setzen | hwmon `pwm1`, `pwm1_enable` (`HPWMI_VICTUS_S_FAN_SPEED_SET_QUERY` = 0x2E) |
| GPU-Leistungsbudget | intern über CTGP / PPAB, gekoppelt an das Thermik-Profil |

`nbfc-linux` wäre ein Rückschritt: es spricht den EC direkt an, braucht ein
modellspezifisches Reverse-Engineering-Profil und kollidiert mit dem Treiber.

## Der Zusammenhang zu Hashcat

Der Treiber schaltet im Profil `performance` zusätzlich **CTGP** (Configurable
TGP) und **PPAB** (Dynamic Boost) der RTX 4060 frei — die GPU bekommt also mehr
Leistungsbudget. Im Balanced-Profil bleibt das aus.

Deshalb steht `hashcat` in `/etc/gpu-offload.d/apps.list` mit dem Zusatz `!perf`.
Der erzeugte Shim startet:

```sh
powerprofilesctl launch -p performance -- /usr/bin/hashcat "$@"
```

Das Profil gilt nur für die Laufzeit und fällt danach automatisch zurück —
kein dauerhafter Akku- und Temperaturnachteil. `powerprofilesctl` braucht dank
polkit kein `sudo`.

## Bedienung

```bash
victus status              # Board-ID, Profil, Lüfterdrehzahlen, Temperaturen
victus diagnose            # falls das Board nicht erkannt wird
sudo victus perf           # Performance-Profil (CTGP/PPAB an)
sudo victus balanced
sudo victus quiet
sudo victus fan max        # Lüfter auf Anschlag
sudo victus fan 180        # manuell, 0–255
sudo victus fan auto       # zurück an den EC
```

## Wenn die Board-ID fehlt

Welche `DMI_BOARD_NAME` das 16-s1902ng meldet, war beim Bau der ISO nicht
bekannt — das steht erst am Gerät fest. Die Liste im Kernel enthält 21 IDs
(`8902`, `8A44`, `8A4D`, `8BAB`, `8B2F`, `8BBE`, `8BC2`, `8BCA`, `8BCD`, `8BD4`,
`8BD5`, `8C76`, `8C77`, `8C78`, `8C99`, `8C9C`, `8D26`, `8D41`, `8D87`, `8E35`).

Ist die eigene nicht dabei, legt `hp-wmi` kein `platform_profile` an.
`victus diagnose` erkennt das und gibt den fertigen Codeblock aus. Weil wir den
Kernel selbst bauen, ist das ein Einzeiler in `prepare()` und ein Rebuild —
kein Blocker.

Die neueren s-Einträge nutzen `victus_s_thermal_params` (`8C99`, `8C9C`) bzw.
`omen_v1_thermal_params` (`8C76`–`8C78`). Falls Profile zwar schalten, aber
nichts bewirken, ist die jeweils andere Variante die richtige.

Funktioniert es: bitte an `platform-driver-x86@vger.kernel.org` melden, dann
landet die ID upstream und der lokale Patch entfällt.

## Was noch offen ist

- **`ryzenadj`** (CPU-TDP-Limits jenseits der Thermik-Profile) ist nur im AUR:
  `paru -S ryzenadj`. Auf Hawk Point funktioniert es, kollidiert aber mit den
  hp-wmi-Profilen — nur eines von beidem verwenden.
- **MUX-Switch:** Das Victus 16-s hat keinen. Die 780M bleibt immer am Display,
  die 4060 läuft ausschließlich über PRIME-Offload. Genau darauf ist das
  GPU-Setup ausgelegt.
