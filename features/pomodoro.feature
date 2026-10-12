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
    And re-enabling starts a fresh default (50/10) Work Block

  Scenario: Reboot mid-phase
    Given a Work Block or Break with a wall-clock deadline was running
    When the session restarts before that deadline
    Then the phase resumes with its original deadline intact

  Scenario: Deadline long past at restore
    Given a Work Block deadline passed while the session was away
    When the machine ticks after restart
    Then the break deadline is anchored to the original expiry instant, not the restart time

  Scenario: Custom values
    Given the popup's custom editor
    When I set any work and break minute pair and start
    Then that one-off pair governs the block exactly like a preset

  Scenario: Preset cap
    Given the user edits presets
    When they try to add a 6th preset
    Then the addition is refused with an explanatory message
