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
