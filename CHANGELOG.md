# Changelog

## 1.0.1 (2026-11-21)

Fixes found by a full test of the downloaded version (install, 1-minute test, news briefing, uninstall):

- Installer: the start-time question no longer rejects valid times (7, 07:30, 7:30 AM, 7pm all work).
- Installer: Roku TV names with special characters display correctly in the TV list.
- News: briefings with more than 8 stories switch to three columns so nothing is cut off; briefings now aim for 8 stories.
- News: the spoken greeting matches the time of day instead of always saying "good morning".

## 1.0.0 (2026-11-21)

First public release.

- Morning dashboard on a Roku TV: clock, weather (Open-Meteo), today's calendar (secret iCal link) and a quote.
- Daily schedule with Task Scheduler that wakes the PC from sleep, turns the TV on over the network (Roku ECP),
  switches to the PC's HDMI input, sends picture and sound to the TV, and puts everything back afterwards.
- Optional spoken news briefing (Ctrl+Alt+N) written by the Claude API with web search, read aloud with a
  Microsoft Edge natural voice. Uses your own Claude Console API key.
- Guided installer: finds Roku TVs automatically, looks up your city, finds the TV's speakers, sets up the
  schedule and keyboard shortcuts, and runs a test.
- If Windows is on its lock screen at start time, the dashboard waits for you to sign in instead of leaving
  the screens half switched. The installer and README explain how to turn off the sign-in after sleep.
- On busy days the schedule shows the next 7 events and skips the "Tomorrow" preview so nothing gets cut off.
