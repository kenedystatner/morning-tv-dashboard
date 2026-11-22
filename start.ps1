# Morning start: TV on, picture and sound to the TV, fresh data, dashboard full screen.
# Run by the daily scheduled task and the Ctrl+Alt+D shortcut.
. (Join-Path $PSScriptRoot "common.ps1")
$Config = Get-DashConfig
$HDMI = [int]$Config.tv.hdmiInput
$Hours = [double]$Config.schedule.hoursOn; if ($Hours -le 0) { $Hours = 3 }

# If Windows is still on its lock screen (it asks for a sign-in after waking from sleep), the dashboard
# can't take over the screen yet. Wait for the sign-in instead of leaving the screens half switched.
# To skip the wait every morning, see README: "Don't ask for a sign-in after sleep".
$deadline = (Get-Date).AddHours($Hours)
$waited = $false
while ((Get-Process -Name LogonUI -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
  if (-not $waited) { "$(Get-Date -Format 's')  PC is locked - waiting for sign-in before showing the dashboard" | Add-Content (Join-Path $Dir "refresh-log.txt"); $waited = $true }
  Start-Sleep 5
}
if ((Get-Date) -ge $deadline) { exit 0 }
if ($waited) { Start-Sleep 5 }

# keep the PC and screen awake until turn-off time
Add-Type -Name Power -Namespace Dash -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
[Dash.Power]::SetThreadExecutionState([uint32]2147483651) | Out-Null

# remember where your windows are, then send the picture to the TV only (your monitor goes dark)
& (Join-Path $Dir "windows.ps1") save
if ($Config.pcHasOwnMonitor) { DisplaySwitch.exe /external; Start-Sleep 4 }

# turn the TV on (retry while Wi-Fi reconnects after waking) and pick the PC's input
for ($i = 0; $i -lt 6; $i++) { if (Invoke-Roku "PowerOn") { break }; Start-Sleep 5 }
Start-Sleep 8
if ($HDMI -gt 0) { Invoke-Roku "InputHDMI$HDMI" | Out-Null; Start-Sleep 3 }

# play sound through the TV speakers (switched back by stop.ps1)
& (Join-Path $Dir "audio.ps1") tv

# download fresh weather + calendar for the dashboard
$Refresh = Join-Path $Dir "refresh-data.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Refresh

# open the dashboard full screen in its own Edge window (your normal browsers are left alone)
$EdgeProfile = Join-Path $Dir "edge-profile"
Stop-ProcessByCommandLine "msedge.exe" $EdgeProfile
Start-Sleep 2
Remove-Item (Join-Path $EdgeProfile "Default\Sessions") -Recurse -Force -ErrorAction SilentlyContinue
$Edge = Get-EdgePath
$Page = ([Uri](Join-Path $Dir "morning-dashboard.html")).AbsoluteUri
Start-Process $Edge -ArgumentList "--kiosk", $Page, "--edge-kiosk-type=fullscreen", "--user-data-dir=`"$EdgeProfile`"",
  "--no-first-run", "--autoplay-policy=no-user-gesture-required"

# keep the weather and calendar fresh until turn-off time
$End = $deadline
while ((Get-Date) -lt $End) { Start-Sleep 600; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Refresh }
[Dash.Power]::SetThreadExecutionState([uint32]2147483648) | Out-Null
