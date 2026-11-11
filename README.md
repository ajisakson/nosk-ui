# NoskUI

Personal UI tweaks for **WoW Forever** (Interface `16001`, Midnight-era client).

## Features

### Threat-colored nameplates

While you're in combat, enemy nameplate health bars are colored by your threat on that unit:

| Threat | Tank | Non-tank |
|---|---|---|
| Securely tanking (3) | green | red |
| Contested — losing aggro (2) or about to pull (1) | yellow | yellow |
| Not tanking (0) / mob on a groupmate | red | green |

Out of combat, or on units you have no threat with, the default Blizzard color is restored.

**Tank detection** (first match wins): manual override → group role → Defensive Stance / Bear Form / Righteous Fury → spec role.

**Secret values:** Midnight-era clients can hide some API results in combat. If `UnitThreatSituation` comes back secret, NoskUI falls back to "is this mob targeting me?" (green/red only, no yellow).

## Commands

- `/nosk role auto|tank|dps` — tank detection mode
- `/nosk threat on|off` — toggle threat coloring
- `/nosk debug` — show detected role and test the threat APIs on your target

## Install

Copy or symlink the `NoskUI/` folder into `World of Warcraft/_forever_/Interface/AddOns/`:

```bash
ln -s "$PWD/NoskUI" "/Applications/World of Warcraft/_forever_/Interface/AddOns/NoskUI"
```
