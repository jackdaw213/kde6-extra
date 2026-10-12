# ADR-0002: Break overlay communication channel — widget-owned LayerShellQt overlay instead of a KWin script

## Status
Accepted (amends ADR-0001; ADR-0001's *goal* — a fullscreen surface that beats true-fullscreen apps — is preserved; its *mechanism* is replaced).

## Context
ADR-0001 mandates that the break overlay be created and raised by a KWin script loaded over the KWin scripting DBus API, because a plain QML window can lose to true-fullscreen applications. The SPEC's overlay contract requires the widget to drive the overlay (show/hide/update + button state) and the overlay to report button intents back (`continuePressed`, `skipConfirmed`, `delayPressed`). That reverse direction needs a reliable channel. Feasibility probes (2026-10, live Plasma 6.7.5 on Arch, Wayland) were run before committing, as the task plan demanded.

## Probe results (all performed live against a real kwin_wayland session)

1. **KWin JS scripts (`/Scripting loadScript(path, name)` + one-time `Scripting.start()` DBus call):**
   - Loadable and unloadable at runtime by absolute path; `isScriptLoaded` reflects state. Scripts do not evaluate until `org.kde.kwin.Scripting.start()` has been called once (deferred-start API).
   - Injected globals verified by round-tripping probe results through `callDBus` to a listener process: `callDBus` ✓, `QTimer` ✓, bare global `readConfig(key, default)` ✓ (note: `KWin.readConfig` is *not* a function in 6.7.5, contrary to older docs).
   - **Cannot render anything**: KWin JS scripts only manipulate existing windows; no window/surface creation API. Useless for an overlay UI on their own.

2. **KWin declarative QML scripts (`loadDeclarativeScript(path, name)`):**
   - QML evaluates (probe code self-reported). A `Window{}` root can appear in kwin's window list — but repeated loads of the same path fail unreliably ("File name case mismatch" from KWin's QML cache; only a *fresh* path loads reliably — timestamped directories would be needed for every show).
   - **The engine is a bare QtQuick sandbox**: `typeof callDBus === "undefined"`, `typeof readConfig === "undefined"`, `typeof workspace === "undefined"`. The only outbound capability is `XMLHttpRequest` as an HTTP client (verified with a GET to a local HTTP server, status 200).
   - `file://` XHR is hard-disabled in the kwin process: *"XMLHttpRequest: Using GET on a local file is disabled by default. Set QML_XHR_ALLOW_FILE_READ to 1 to enable this feature."* The env var must be set before kwin starts; it cannot be set at runtime from outside.

3. **No localhost server can exist on the widget side.** The task's preferred design (widget writes state JSON, overlay XHR-polls it; overlay POSTs intents; widget polls intents) needs *something* to serve HTTP. Plasmoid QML has no socket/server API; no stock session-bus relay service exists; a purpose-built helper daemon would be a new always-running component outside the approved architecture.

4. **Consequence:** in the ADR-0001 architecture the overlay can display *static* content (initial state can be baked into a freshly-written QML file) and be dismissed from the widget side (`unloadScript` over DBus), but **the overlay's interactive controls (Continue, Skip confirmation, Delay break) have no channel to report user intent to the widget**. The overlay also cannot self-dismiss. That fails the SPEC's overlay contract (user stories 13–18) and the "reliable interactivity" bar defined by the task plan.

## Decision
The break overlay is implemented **inside the plasmoid process** as a fullscreen **LayerShellQt** QML window (`org.kde.layershell` module, shipped with Plasma): `layer = LayerOverlay`, `keyboardInteractivity = None`, all four anchors anchored, `exclusionZone = -1` (announces no exclusive zone — the surface covers the full screen including panel strips without reserving layout space for anything). The overlay is constructed once with layer properties set before the surface attaches and is reused across breaks by toggling `visible`.

Rationale, option by option:
- **Chosen — widget-owned LayerShellQt overlay.** Layer-shell overlay surfaces are drawn *above normal windows, including true-fullscreen ones* — this is the same Wayland layer mechanism Plasma's own OSD uses, so it satisfies ADR-0001's actual goal ("blows the entire screen", beats fullscreen apps). Zero IPC: overlay buttons call the machine controller in-process, which deletes the entire fragile communication layer and makes all three controls exact and synchronous. Cost: the mechanism is guaranteed by the Wayland protocol rather than by KWin's window management; and *attaching a layer surface from the plasmashell process* is not verifiable from a sandboxed dev shell — it is the one item validated only by a live post-install test (fallback below covers failure).
- **Rejected — keep ADR-0001 mechanism as a visual-only overlay and move Continue/Skip/Delay to the panel popup.** Directly contradicts the product promise: the enforce-overlay-with-buttons UX is the core of user stories 13–18.
- **Rejected — helper daemon (local HTTP relay between widget and KWin script).** Adds a resident process with lifetime management, packaging and failure modes of its own, to enable a KWin-script route whose show/reload behavior is itself flaky (cache quirk above). Worst parts-to-benefit ratio.
- **Fallback (documented, not silent):** if layer-shell attachment from the plasmashell process proves impossible in live use, the overlay window degrades to a plain always-on-top QML window (`WindowStaysOnTopHint`-equivalent flags). That weakens enforcement exactly as ADR-0001 warned (true-fullscreen apps can cover it) — if this fallback is ever activated it must be stated in the project's issues/readme, never adopted silently.

## Consequences
- No KWin script ships with the plasmoid; no DBus KWin-scripting calls at runtime.
- The overlay's Continue/Skip/Delay handlers are plain function calls into the controller; their behavior is exactly the machine's semantics (e.g. Continue disabled until the wall-clock break deadline passes, self-enabling after a restart).
- `plasmoid/contents/ui/Overlay.qml` sets layer properties at construction and toggles only `visible`; a `layerSurfaceDefined` flag + console warning records whether the layer surface actually attached, so a silent degradation to a plain window cannot go unnoticed.
- KWin scripting DBus probing remains documented here for future maintainers wondering why the obvious "official" route was not used on Plasma 6.7.
