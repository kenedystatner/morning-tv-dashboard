# Changelog

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
