# ADR-0001: Break overlay beats fullscreen apps

## Status
Amended by [ADR-0002](0002-overlay-communication-channel.md): the overlay is owned by the plasmoid via LayerShellQt (Wayland layer-shell, Overlay layer) instead of a KWin script — KWin-script interactivity was proven infeasible on Plasma 6.7.5. The goal below is unchanged and still honored.

## Original decision (superseded)
The break overlay is created and raised by a small KWin script (loaded over the KWin scripting DBus API) that renders a fullscreen, keepAbove window on the display. The panel widget drives it by state, not by owning the overlay window itself.

## Context
The product's core promise is that when a Work Block expires, a fullscreen overlay "blows the entire screen" and the user cannot avoid seeing it. On Plasma 6, a plain fullscreen QML window created from within a Plasmoid can be covered by true-fullscreen applications (games, video players, presentations), which would silently defeat the whole feature.

## Decision
The break overlay renders on a Wayland layer-shell surface at the Overlay layer, guaranteeing it sits above all application windows including true-fullscreen apps.

## Consequences
- Overlay reliability is strong even over fullscreen apps; this was the user's explicit expectation ("blow the entire screen").
- Alternatives rejected: a plain QML window from the Plasmoid (loses to true-fullscreen apps); a KWin-script overlay (proven infeasible for interactive buttons — no intent channel exists from KWin declarative scripts back to the widget; see ADR-0002's probe evidence).
