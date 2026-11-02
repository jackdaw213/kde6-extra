# Vendor notes

- **Origin:** https://github.com/Powermayer/keep-above-outline
- **Fork point:** commit `18c0618` (Plasma-6.8 merge), upstream version 1.3.0
- **License:** GPL-3.0-or-later, © Matthias Bauer — preserved in `LICENSE`
  and in the SPDX headers of every source file.
- **Reason:** research (2025-11) found upstream already implements the
  keep-above halo indicator exactly as wanted; vendoring instead of building
  from scratch avoids re-solving the KWin 6.8 Wayland rendering and
  repaint-damage problems upstream already handles.

## Files dropped from upstream

- `install.sh`, `how_to_install.txt` — multi-distro helper; replaced by the
  Arch-specific steps in `README.md`.
- `screenshots/keep-above-outline_sample.gif` (4 MB) — upstream demo; kept
  the config screenshot only.

## Changes applied

| File | Change |
| --- | --- |
| `keepaboveoutline.cpp` | `UseAccentColor` default `true` → `false`; `CustomColor` default `#3daee9` → `#ffb300` (amber) |
| `keepaboveoutline_config.cpp` | same defaults for the settings module |
| `keepaboveoutlineconfig.kcfg` | same defaults for the schema |
| `keepaboveoutline_config.ui` | same defaults for the checkbox/color button |
| `CMakeLists.txt` | project version aligned to 1.3.0 |

Upstream plugin id `keep-above-outline` is unchanged on purpose: rebases onto
future upstream releases stay clean, and the id is what the KCM's DBus
`reconfigureEffect` call targets.
