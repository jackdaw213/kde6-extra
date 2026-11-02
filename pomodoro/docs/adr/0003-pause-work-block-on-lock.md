# ADR-0003: Pause a Work Block while the screen is locked

## Status
Accepted (amends the Wall-clock deadline rule in `CONTEXT.md` and `docs/SPEC.md`).

## Context
Every phase stores an absolute wall-clock deadline, and the project treats that rule as a guarantee: logout, reboot, and plasmashell restart never lose or stretch a running phase. The operator now wants a different promise for work time: away time must not count as work. A locked screen means the user is not working, so a Work Block that keeps running behind the lock screen charges the user for time they did not work.

The same screen-lock signal drives the new Auto-start feature: an unlocked session is Presence, and sustained Presence starts a Work Block. The time model must stay coherent with that presence model.

## Decision
- A screen lock pauses a running **Work Block**: the machine freezes the remaining work time and the remaining Desk Reminder time. Both deadlines stop.
- A screen unlock resumes both from the frozen values: the new deadlines are the unlock instant plus the frozen remaining time. The user receives the full remaining block.
- The paused flag and the frozen remaining times persist in the state snapshot. A plasmashell restart, logout, or reboot while paused restores the Paused Work Block unchanged. Presence is not persisted.
- A **Break** keeps its wall-clock deadline. Real rest time away counts as rest. A finished-break wait has no deadline and is never paused.
- The pure state machine owns pause and resume. The host reports only the raw lock state through `screenLocked` and `screenUnlocked` intents.
- Auto-start uses the same Presence signal. A manual Disable sets the machine to unarmed; a screen lock re-arms it; sustained Presence after the next unlock starts the Default Preset.

## Consequences
- A Work Block's deadline now shifts by the total paused duration. The wall-clock guarantee applies to unpaused phases and to Breaks, not to a Paused Work Block.
- The state snapshot gains the paused flag, the frozen work time, the frozen desk time, and the Auto-start arm flag. The snapshot validator must accept a paused work phase with no active deadline.
- The panel's remaining-time display must read the frozen work time while paused.
- A pending Delay Break pauses with the block and survives the pause.
- Alternatives rejected: keep the wall-clock deadline while locked (rejected by the operator: away time is not work); pause every phase including Breaks (rejected: away time during a Break is rest).
