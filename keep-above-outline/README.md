# Keep Above Outline (vendored)

KWin effect that draws a colored outline around every window with **Keep
Above** (always-on-top) enabled, so pinned windows are identifiable at a
glance. Shows up in **System Settings → Window Management → Desktop
Effects → Appearance**, with a settings page for color, border width and
corner radius.

Vendored from [Powermayer/keep-above-outline](https://github.com/Powermayer/keep-above-outline)
(GPL-3.0-or-later, © Matthias Bauer), fork point `18c0618` / v1.3.0.
See [VENDOR-NOTES.md](VENDOR-NOTES.md) for what was changed.

## Local changes vs upstream

- Default color is amber `#ffb300` instead of Breeze blue.
- **Use accent color** defaults to **off**, so the amber shows out of the box.

## Build (Arch, Wayland)

Dependencies ship with the normal Arch KDE packages (`kwin`, `qt6-base`,
`qt6-declarative`, `kcoreaddons`, `kconfigwidgets`, `kcmutils`,
`extra-cmake-modules`); no separate dev packages are needed.

```sh
cd keep-above-outline
cmake -B build -S . -DKWIN_BACKEND=WAYLAND -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
```

X11 sessions: `-DKWIN_BACKEND=X11` instead (KWin X11 6.7+ headers need a
C++23 compiler).

## Install

`cmake --install` needs root because the plugin goes next to KWin's own
effects (`/usr/lib/qt6/plugins/kwin/effects/plugins/` on Arch). After
installing:

1. System Settings → Window Management → Desktop Effects.
2. Enable **Keep Above Outline** (Appearance category).
3. Gear icon: color, border width (1–20 px), corner radius (0–30 px).

Settings persist in `kwinrc` under `[Effect-keep-above-outline]`:

```sh
kwriteconfig6 --file kwinrc --group Effect-keep-above-outline --key CustomColor "#ffb300"
```

## Maintenance

- **Rebuild after every KWin upgrade** — effect plugins link against the
  installed KWin and can fail to load after ABI changes.
- Keep the effect API compat defines in `CMakeLists.txt` in sync when
  rebasing onto a new upstream release.
