# Turn-off: TV off, dashboard closed, sound and picture back to normal, windows put back.
# Run by the daily scheduled task and the Ctrl+Alt+X shortcut.
. (Join-Path $PSScriptRoot "common.ps1")
$Config = Get-DashConfig

Invoke-Roku "PowerOff" | Out-Null
# stop any news briefing that's being read
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir "news-stop.ps1")
# close the dashboard window
Stop-ProcessByCommandLine "msedge.exe" (Join-Path $Dir "edge-profile")
# sound back to your usual output, picture back on your monitor only
& (Join-Path $Dir "audio.ps1") restore
if ($Config.pcHasOwnMonitor) { DisplaySwitch.exe /internal; Start-Sleep 5 }
# put your windows back where they were
& (Join-Path $Dir "windows.ps1") restore
# end the morning script (it keeps the PC awake and refreshes data)
Stop-ProcessByCommandLine "powershell.exe" (Join-Path $Dir "start.ps1")
