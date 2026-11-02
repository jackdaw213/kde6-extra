# kde6-extra

My KDE Plasma 6 add-ons and modifications. One folder per extension, each
self-contained; this repo is the single home for everything I change on my
KDE desktop.

- **pomodoro/** — enforced Pomodoro timer as a Plasma 6 panel widget
  (`org.kde.plasma.pomodoro`). Work Blocks expire into a fullscreen rest
  overlay that pauses your media, waits as long as you actually rest, and
  survives reboots on wall-clock deadlines. Presence auto-start, lock-paused
  work, Desk Reminder, chimes. Formerly the `PomodoroKDE` repo.
- **snap-assist/** — KWin script which suggests other window thumbnails on
  snap (Plasma 6 port of emvaized's kde-snap-assist; `upstream/` keeps a
  pristine copy of the original and stays untracked). Formerly the
  `kde6-snap-assist` repo.
- **keep-above-outline/** — KWin effect drawing an outline around every
  window with Keep Above enabled (vendored from Powermayer/keep-above-outline,
  GPL-3.0-or-later; amber default). Makes pinned windows identifiable at a
  glance.

Install steps live in each folder's README.
