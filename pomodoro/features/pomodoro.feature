Feature: Pomodoro panel widget
  Enforced work/rest cycles from a Plasma 6 panel widget.

  Background:
    Given the widget is enabled

  Scenario: Starting the default preset
    Given the widget is idle
    When I click a preset in the popup
    Then a Work Block of that preset's work length starts
    And the panel icon shows the remaining time

  Scenario: Work block expiry blows the screen
    Given a Work Block is running
    When the wall-clock deadline passes
    Then the Break overlay covers the entire screen
    And the break deadline is the expiry instant plus the preset's break length
    And all MPRIS media is paused
    And a chime plays

  Scenario: Continue is locked until the break ends
    Given the Break overlay is up
    Then the Continue button is disabled and grayed out
    When the break deadline passes
    Then the Continue button becomes enabled and stays enabled indefinitely

  Scenario: Taking a longer break naturally
    Given the break timer has finished and the overlay still waits
    When I press Continue at any later moment
    Then a fresh Work Block of the current preset starts immediately

  Scenario: Skipping a break in flow
    Given the Break overlay is up and the break timer is still running
    When I press Skip and confirm
    Then the overlay closes and a fresh Work Block starts immediately
    And the cycle advances as if the break had run fully

  Scenario: Delaying a break
    Given the Break overlay is up
    When I press "Delay break 5 minutes"
    Then the overlay closes, the break is not counted, and work resumes with the deadline extended 5 minutes
    And pressing it again extends by 5 more minutes

  Scenario: Cutting a delayed period short
    Given a Delay Break is active with time remaining
    When I choose "Start break now" in the panel popup
    Then the pending break starts immediately

  Scenario: Large break on cadence
    Given the cycle counts every Work Block whose break actually started
    When the 4th Work Block's break starts
    Then it is a Large Break
    And its length is the preset's explicit large-break value if set
    And otherwise derived: break ≤6 min gives 20, 7–12 gives 30, ≥13 gives 40

  Scenario: Skipped break keeps cadence honest
    Given a work block whose break was skipped
    When the next work block completes
    Then the cycle has advanced by two

  Scenario: Disable for a meeting
    Given any state
    When I choose "Disable for now"
    Then all timing, overlay, and media-pause behavior is suspended
    And re-enabling starts a fresh Work Block of the Default Preset

  Scenario: Reboot mid-phase
    Given a Work Block or Break with a wall-clock deadline was running
    When the session restarts before that deadline
    Then the phase resumes with its original deadline intact

  Scenario: Deadline long past at restore
    Given a Work Block deadline passed while the session was away
    When the machine ticks after restart
    Then the break deadline is anchored to the original expiry instant, not the restart time

  # Superseded (removed with the Custom row in the card overhaul): the Custom
  # one-off editor is gone — user presets cover arbitrary (work, break) pairs,
  # and the machine still starts any preset payload (restored snapshots).

  # Superseded by SPEC-002: the card holds exactly six fixed slots (three
  # locked Built-ins + three user slots); there is no open-ended list to
  # overflow and no refusal path exists anymore.

  Feature extension: preset grid, in-card management, Desk Reminder, chime (SPEC-002)

  Scenario: Six preset slots in a 2x3 grid
    Given the widget is idle
    When I open the popup
    Then presets appear as two rows of three with slightly larger font
    And the three Built-ins (50/10, 25/5, 45/15) are always present and undeletable

  Scenario: Clicking a grid preset starts it
    Given the widget is idle
    When I click a preset in the grid
    Then a Work Block of that preset's work length starts immediately

  Scenario: Default preset is chosen, not positional
    Given the popup card is open
    When I set the Default Preset marker on any of the six slots
    Then that preset is starred in the grid
    And re-enabling after "Disable for now" starts that preset

  Scenario: Managing user presets in the card
    Given the popup card is open
    When I add a user preset (at most three exist)
    Then it occupies the user slot whose row offered the Add preset button
    And it is created as a 30/5 rhythm — never a Built-in duplicate
    When I edit or delete a user preset in the card
    Then the change is immediate and the grid reflects it
    But Built-in presets expose no edit or delete controls

  Scenario: User preset labels derive from the minutes
    Given the popup card is open
    When I create or edit a user preset to 40 work minutes and 6 break minutes
    Then it is labeled "40/6" in the grid and the star picker — its row identifies it by its Work and Break spin values
    And no control offers a custom preset name
    When I tune a user preset's minutes onto a Built-in's exact rhythm
    Then the change is refused with "change the minutes" guidance

  Scenario: Per-preset Large break, 0 means automatic
    Given the popup card is open
    When I set a user preset's Large break to 0
    Then its scheduled Large Break length is derived automatically: break ≤6 min gives 20, 7–12 gives 30, ≥13 gives 40
    When I set the user preset's Large break to 45
    Then its scheduled Large Break lasts 45 minutes

  Scenario: No presets page in Configure
    Given I open the widget's Configure dialog
    Then there is no Presets page

  Scenario: Desk reminder counts only during work
    Given the Desk Reminder is enabled with a 30 minute interval
    When a Work Block starts
    Then the desk countdown begins at 30 minutes
    And it advances only while the phase is work
    When a new Work Block starts
    Then the desk countdown is back to 30 minutes

  Scenario: Desk overlay prompts a height change
    Given a Work Block is running and the desk countdown reaches zero
    Then a fullscreen overlay appears
    And it says to change the standing desk height by doing the reverse of what I'm doing now
    And a chime plays
    And the Work Block keeps running underneath

  Scenario: Acknowledging the desk overlay
    Given the Desk Overlay is up
    When I press "Done — I switched"
    Then the overlay goes away
    And the desk countdown restarts at the full interval

  Scenario: Break outranks the desk overlay
    Given the Desk Overlay is up
    When the Work Block expires
    Then the overlay shows Break content and the break is enforced as usual
    And the desk countdown restarts with the next fresh Work Block

  Scenario: Desk reminder can be switched off
    Given the Desk Reminder toggle is off in the card
    When Work Blocks run and expire
    Then no desk countdown and no Desk Overlay ever occur

  Scenario: Desk reminder survives a restart
    Given a Work Block and a partly elapsed desk countdown were running
    When the session restarts before the desk deadline
    Then the desk countdown resumes with its original wall-clock deadline intact

  Scenario: Pleasant short chime
    Given a Break starts or the Desk Overlay appears
    Then a bundled soft piano-style chime plays once, lasting roughly 2 to 3 seconds

  Feature extension: Presence-driven auto-start and lock-paused Work Blocks (SPEC-003)

  Scenario: Auto-start after the Presence window
    Given the widget is idle and auto-start is on with a 5 minute window
    When the session stays unlocked for 5 minutes
    Then a Work Block of the Default Preset starts
    And one desktop notification names the started preset
    And no chime plays

  Scenario: Presence window resets on lock
    Given the widget is idle and 3 minutes of the Presence window have elapsed
    When the session locks
    Then the Presence window is reset
    And no Work Block starts

  Scenario: Auto-start respects a manual Disable
    Given I chose "Disable for now" for a meeting
    When the session stays unlocked for 30 minutes
    Then no Work Block starts

  Scenario: Auto-start re-arms after a lock
    Given I chose "Disable for now" and the session has since locked once
    When the session stays unlocked for 5 minutes after that lock
    Then a Work Block of the Default Preset starts

  Scenario: Auto-start never interrupts timing
    Given a Work Block, a Break, or the finished-break wait is active
    When the session stays unlocked for longer than the Presence window
    Then no auto-start occurs

  Scenario: Auto-start uses the Default Preset
    Given auto-start is on and the star marks the 25/5 preset
    When the Presence window elapses
    Then a 25/5 Work Block starts

  Scenario: Missing star falls back
    Given auto-start is on and the star is missing or invalid
    When the Presence window elapses
    Then a 50/10 Work Block starts

  Scenario: Lock pauses the Work Block
    Given a Work Block with 20 minutes remaining
    When the session locks
    Then the Work Block remaining time freezes at 20 minutes
    And the desk countdown freezes

  Scenario: Unlock resumes the Work Block
    Given a Paused Work Block with 20 minutes remaining
    When the session unlocks 30 minutes later
    Then the Work Block resumes with 20 minutes remaining
    And the desk countdown resumes from its frozen time

  Scenario: A delayed break survives the pause
    Given a delayed Work Block with a pending Break
    When the session locks and unlocks
    Then the pending Break is still pending

  Scenario: A Delay intent on a paused block extends the frozen time
    Given a paused Work Block with 4 minutes remaining and a pending Break
    When a Delay intent reaches it while it is paused
    Then the frozen remaining time becomes 9 minutes
    And unlocking resumes the Work Block with that longer remaining time

  Scenario: A lock at the work deadline does not pause a finished block
    Given a Work Block whose deadline has been reached
    When the session locks
    Then the Work Block does not pause
    And the Break starts at the original expiry on the next tick

  Scenario: A desk countdown due at the lock instant keeps its prompt
    Given a Work Block whose desk countdown reaches zero as the session locks
    When the session unlocks
    Then the Desk Overlay appears on the next tick
    And the desk countdown is not restarted at a full interval

  Scenario: A Break is never paused
    Given a Break with 8 minutes remaining
    When the session locks for 10 minutes
    Then the Break deadline is unchanged
    And after unlock the overlay waits with Continue enabled

  Scenario: A Paused Work Block survives a restart
    Given a Paused Work Block with 12 minutes remaining
    When plasmashell restarts
    Then the Work Block is still paused with 12 minutes remaining
    When the session unlocks
    Then the Work Block resumes with 12 minutes remaining

  Scenario: Auto-start can be switched off
    Given the auto-start switch is off in the card
    When the session stays unlocked for an hour
    Then no Work Block starts

  Scenario: Auto-start minutes stay in range
    Given the auto-start delay is edited in the card
    When the value is outside 1 to 60
    Then the stored value stays within 1 to 60

  Scenario: Lock source unavailable
    Given the lock state cannot be read
    Then auto-start and Work Block pause are off
    And manual start, continue, skip, disable, and enable still work
    And a Work Block already paused stays frozen until Disable and Enable

  Scenario: The lock source recovers
    Given a temporary lock-source outage cleared the Presence window
    When the source returns while the session stays unlocked
    Then a fresh Presence window opens
    And after the window Auto-start can fire again

  Feature extension: Working-hours gate for Auto-start (SPEC-004)

  Scenario: Auto-start fires inside Working hours
    Given the widget is idle and auto-start is on with a 5 minute window
    When the Presence window elapses at 10:00 local time
    Then a Work Block of the Default Preset starts

  Scenario: Auto-start does not fire outside Working hours
    Given the widget is idle and auto-start is on with a 5 minute window
    When the Presence window elapses at 08:00 local time
    Then no Work Block starts
    And the Presence window stays open

  Scenario: Presence accrued before 9:00 counts
    Given the widget is idle and auto-start is on with a 5 minute window
    When the session unlocks at 08:56 local time
    And the Presence window has elapsed by 09:00 local time
    Then a Work Block of the Default Preset starts at 09:00

  Scenario: The 17:00 edge is exclusive and defers to the next morning
    Given the widget is idle and auto-start is on with a 5 minute window
    When the Presence window elapses at 17:00 local time
    Then no Work Block starts
    When the window is still elapsed the next morning at 09:00 local time
    Then a Work Block of the Default Preset starts

  Scenario: A block started before 17:00 is not clipped
    Given the Presence window elapses at 16:59 local time
    Then the Work Block starts with its full work length
    And it is not cut short when 17:00 passes

  Scenario: The re-armed Disabled path respects Working hours
    Given I chose "Disable for now" and the session has since locked once
    When the Presence window elapses at 20:00 local time
    Then no Work Block starts
    When the window is still elapsed at 09:00 the next morning
    Then a Work Block of the Default Preset starts

  Scenario: The gate applies every day
    Given the widget is idle and auto-start is on
    When the Presence window elapses on a Saturday at 10:00 local time
    Then a Work Block of the Default Preset starts

  Scenario: Manual starts ignore the gate
    Given the widget is idle at any hour outside Working hours
    When I click a preset, Enable, Continue, Skip, or Delay
    Then the action works exactly as it does inside Working hours
