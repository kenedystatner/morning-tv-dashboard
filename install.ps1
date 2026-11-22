<#
  Morning TV Dashboard - installer
  Run it once (double-click install.bat, or see README.md). Run it again any time to change settings.

  It will:
    - find your Roku TV on the network (or let you type its IP address)
    - ask which HDMI input the PC is plugged into
    - look up your city's coordinates and time zone (free Open-Meteo geocoding, no key)
    - help you pick the TV's speakers so the dashboard's sound plays on the TV
    - optionally save your calendar's secret iCal link and your own Claude Console API key
      (into calendar-link.txt / claude-api-key.txt, never into config.json)
    - set up the daily morning schedule and the keyboard shortcuts
    - write config.json and offer to run a test
#>
param([switch]$AdminStep, [switch]$DisableMouseWake)

$Dir = $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

# ------------------------------------------------------------------------------------------
# Administrator-only part (started by the main installer with a Windows permission prompt)
# ------------------------------------------------------------------------------------------
if ($AdminStep) {
  # allow scheduled tasks to wake the PC from sleep (plugged in and on battery)
  powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
  powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
  powercfg /SETACTIVE SCHEME_CURRENT | Out-Null
  if ($DisableMouseWake) {
    powercfg /devicequery wake_armed |
      Where-Object { $_ -match "mouse|basilisk|razer|logitech|deathadder|viper|g502|mx master" -and $_ -notmatch "keyboard" } |
      ForEach-Object { powercfg /devicedisablewake "$_" }
  }
  exit 0
}

# ------------------------------------------------------------------------------------------
# Small helpers for questions
# ------------------------------------------------------------------------------------------
function Say([string]$Text, [string]$Color = "Gray") { Write-Host $Text -ForegroundColor $Color }
function Title([string]$Text) { Write-Host ""; Write-Host "== $Text ==" -ForegroundColor Cyan }
function Ask([string]$Question, $Default) {
  $suffix = if ($null -ne $Default -and "$Default" -ne "") { " [$Default]" } else { "" }
  $a = Read-Host "$Question$suffix"
  if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
  return $a.Trim()
}
function YesNo([string]$Question, [bool]$Default = $true) {
  $hint = if ($Default) { "Y/n" } else { "y/N" }
  while ($true) {
    $a = Read-Host "$Question ($hint)"
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    if ($a -match '^(y|yes)$') { return $true }
    if ($a -match '^(n|no)$') { return $false }
  }
}
function Pick([string[]]$Choices, [string]$Question) {
  for ($i = 0; $i -lt $Choices.Count; $i++) { Say ("  {0}. {1}" -f ($i + 1), $Choices[$i]) White }
  while ($true) {
    $a = Read-Host $Question
    $n = 0
    if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $Choices.Count) { return $n - 1 }
    Say "  Please type a number from 1 to $($Choices.Count)." Yellow
  }
}
function Roku([string]$Ip, [string]$Key) {
  try { Invoke-WebRequest -UseBasicParsing -Method Post -TimeoutSec 5 -Uri "http://${Ip}:8060/keypress/$Key" | Out-Null; $true } catch { $false }
}
function Get-RokuInfo([string]$Ip) {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 4 -Uri "http://${Ip}:8060/query/device-info"
    $x = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())   # names can contain non-English characters
    $get = { param($tag) if ($x -match "<$tag>(.*?)</$tag>") { $Matches[1] } else { "" } }
    $name = & $get "user-device-name"; if (-not $name) { $name = & $get "friendly-device-name" }
    $model = & $get "friendly-model-name"; if (-not $model) { $model = & $get "model-name" }
    [pscustomobject]@{ Ip = $Ip; Name = $name; Model = $model; IsTv = ((& $get "is-tv") -eq "true") }
  } catch { $null }
}

# Find Roku devices with SSDP (the same discovery the Roku phone app uses). The search is sent
# from each of this PC's network adapters, because a plain socket often picks the wrong one.
function Search-Ssdp([string]$BindIp) {
  $ips = @()
  try {
    $udp = if ($BindIp) { [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([Net.IPAddress]::Parse($BindIp), 0)) }
           else { [System.Net.Sockets.UdpClient]::new() }
  } catch { return @() }
  try {
    $udp.Client.ReceiveTimeout = 700
    $msg = "M-SEARCH * HTTP/1.1`r`nHost: 239.255.255.250:1900`r`nMan: `"ssdp:discover`"`r`nST: roku:ecp`r`nMX: 2`r`n`r`n"
    $bytes = [Text.Encoding]::ASCII.GetBytes($msg)
    $group = [System.Net.IPEndPoint]::new([Net.IPAddress]::Parse("239.255.255.250"), 1900)
    for ($k = 0; $k -lt 3; $k++) { [void]$udp.Send($bytes, $bytes.Length, $group); Start-Sleep -Milliseconds 250 }
    $until = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $until) {
      try {
        $from = [System.Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        $reply = [Text.Encoding]::ASCII.GetString($udp.Receive([ref]$from))
        if ($reply -match '(?im)^LOCATION:\s*http://([0-9.]+):8060') { $ips += $Matches[1] }
      } catch { }
    }
  } catch { } finally { $udp.Close() }
  $ips
}
function Find-Rokus {
  $local = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | ForEach-Object { $_.IPAddress })
  $all = @()
  foreach ($a in $local) { $all += Search-Ssdp $a }
  if ($all.Count -eq 0) { $all += Search-Ssdp "" }
  foreach ($ip in ($all | Sort-Object -Unique)) { $info = Get-RokuInfo $ip; if ($info) { $info } }
}

# Settings from an earlier run are offered as defaults.
$Old = $null
$ConfigPath = Join-Path $Dir "config.json"
if (Test-Path $ConfigPath) { try { $Old = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }

# Files downloaded in a ZIP are marked as "from the internet"; unblock this folder's scripts.
Get-ChildItem $Dir -File | Unblock-File -ErrorAction SilentlyContinue

Clear-Host
Say "Morning TV Dashboard setup" Cyan
Say "Answer a few questions. Press Enter to accept the suggestion shown in [brackets]."
Say "Before you start: turn the TV on, connect it to the same Wi-Fi as this PC, and on the TV go to"
Say "Settings > System > Advanced system settings > Control by mobile apps and set it to Enabled."

$EdgePath = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
            Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $EdgePath) { Say "Microsoft Edge was not found. The dashboard runs in Edge; please install it first." Yellow }

# ------------------------------------------------------------------------------------------
# 1. The TV
# ------------------------------------------------------------------------------------------
Title "1. Your Roku TV"
Say "Looking for Roku TVs on your network..."
$found = @(Find-Rokus | Sort-Object { -not $_.IsTv }, Name)
$TvIp = $null
if ($found.Count -gt 0) {
  $choices = @($found | ForEach-Object { "{0}  ({1}, {2})" -f $(if ($_.Name) { $_.Name } else { "Roku" }), $_.Model, $_.Ip })
  $choices += "None of these - I'll type the IP address"
  $i = Pick $choices "Which one is the TV for the dashboard?"
  if ($i -lt $found.Count) { $TvIp = $found[$i].Ip }
} else {
  Say "No Roku found automatically (some routers block discovery)." Yellow
}
while (-not $TvIp) {
  Say "On the TV: Settings > Network > About shows its IP address (it looks like 192.168.1.42)."
  $ip = Ask "TV IP address" $(if ($Old) { $Old.tv.ip } else { "" })
  if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { Say "  That doesn't look like an IP address." Yellow; continue }
  $info = Get-RokuInfo $ip
  if ($info) { Say "  Found: $($info.Name) ($($info.Model))" Green; $TvIp = $ip }
  else {
    Say "  No Roku answered at $ip. Check the TV is on, on the same Wi-Fi, and 'Control by mobile apps' is Enabled." Yellow
    if (YesNo "  Use $ip anyway?" $false) { $TvIp = $ip }
  }
}

$hdmiDefault = if ($Old) { $Old.tv.hdmiInput } else { 1 }
while ($true) {
  $h = Ask "Which HDMI input on the TV is the PC plugged into? (number printed next to the port, 0 = don't switch inputs)" $hdmiDefault
  $n = 0; if ([int]::TryParse("$h", [ref]$n) -and $n -ge 0 -and $n -le 8) { $Hdmi = $n; break }
  Say "  Please type a number like 1, 2 or 3." Yellow
}
$OwnMonitor = YesNo "Does this PC also have its own monitor, besides the TV? (the monitor goes dark while the dashboard is on)" $(if ($Old) { [bool]$Old.pcHasOwnMonitor } else { $true })

# ------------------------------------------------------------------------------------------
# 2. Location for the weather
# ------------------------------------------------------------------------------------------
Title "2. Your city (for the weather)"
$Location = $null
while (-not $Location) {
  $city = Ask "City" $(if ($Old) { $Old.location.city } else { "" })
  if (-not $city) { continue }
  try {
    $r = Invoke-RestMethod -TimeoutSec 15 -Uri ("https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&format=json&name=" + [Uri]::EscapeDataString($city))
    $hits = @($r.results | Where-Object { $_ })
  } catch { $hits = @(); Say "  Couldn't reach the geocoding service: $($_.Exception.Message)" Yellow }
  if ($hits.Count -eq 0) {
    Say "  No match for '$city'. Try a nearby larger city, or add the state/country (e.g. 'Springfield Illinois')." Yellow
    if (YesNo "  Type the coordinates yourself instead?" $false) {
      $lat = [double](Ask "  Latitude (e.g. 39.80)" "")
      $lon = [double](Ask "  Longitude (e.g. -89.64)" "")
      $tzName = Ask "  Time zone (e.g. America/Chicago)" ""
      $cc = Ask "  Country code (e.g. US)" "US"
      $Location = [ordered]@{ city = $city; region = ""; country = $cc; latitude = $lat; longitude = $lon; timeZone = $tzName }
    }
    continue
  }
  $labels = @($hits | ForEach-Object { (@($_.name, $_.admin1, $_.country) | Where-Object { $_ }) -join ", " })
  $labels += "None of these - search again"
  $i = Pick $labels "Which one?"
  if ($i -ge $hits.Count) { continue }
  $g = $hits[$i]
  $Location = [ordered]@{ city = $g.name; region = "$($g.admin1)"; country = "$($g.country_code)"
                          latitude = [Math]::Round([double]$g.latitude, 4); longitude = [Math]::Round([double]$g.longitude, 4); timeZone = $g.timezone }
  Say "  $($labels[$i]) - time zone $($g.timezone)" Green
}
$unitDefault = if ($Old) { if ($Old.units -eq "celsius") { "C" } else { "F" } } elseif ($Location.country -in @("US", "LR", "MM")) { "F" } else { "C" }
$Units = if ((Ask "Temperatures in F or C?" $unitDefault) -match '^[cC]') { "celsius" } else { "fahrenheit" }

# ------------------------------------------------------------------------------------------
# 3. The TV's speakers
# ------------------------------------------------------------------------------------------
Title "3. Sound through the TV"
Say "The news briefing is read aloud. To play it on the TV, pick the TV's sound device."
Say "The TV only shows up as a sound device while it is on and showing this PC."
$SoundDevice = if ($Old) { "$($Old.tv.soundDevice)" } else { "" }
if (YesNo "Turn the TV on and show this PC on it for a moment to find its speakers?" $true) {
  & (Join-Path $Dir "windows.ps1") save
  if ($OwnMonitor) { DisplaySwitch.exe /extend; Start-Sleep 3 }
  [void](Roku $TvIp "PowerOn"); Start-Sleep 8
  if ($Hdmi -gt 0) { [void](Roku $TvIp "InputHDMI$Hdmi") }
  Say "  Waiting for Windows to see the TV..."; Start-Sleep 8
  $names = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir "audio.ps1") names | Where-Object { $_ })
  if ($OwnMonitor) { DisplaySwitch.exe /internal; Start-Sleep 4 }
  & (Join-Path $Dir "windows.ps1") restore
  [void](Roku $TvIp "PowerOff")
  if ($names.Count -gt 0) {
    Say "Sound devices on this PC (the TV is usually the one with its model name or 'HDMI' / 'High Definition Audio'):"
    $i = Pick (@($names) + "Skip - keep sound on this PC") "Which one is the TV?"
    if ($i -lt $names.Count) {
      $core = $names[$i] -replace '^\s*\d+\s*-\s*', '' -replace '\s*\([^)]*\)\s*$', ''
      if (-not $core) { $core = $names[$i] }
      $SoundDevice = [regex]::Escape($core.Trim())
      Say "  TV speakers: $core" Green
    } else { $SoundDevice = "" }
  } else { Say "  Couldn't list sound devices; skipping. Sound will stay on this PC." Yellow }
}

# ------------------------------------------------------------------------------------------
# 4. Schedule
# ------------------------------------------------------------------------------------------
Title "4. Morning schedule"
while ($true) {
  $t = Ask "What time should the TV turn on? (24-hour, e.g. 07:30)" $(if ($Old) { $Old.schedule.startTime } else { "08:00" })
  # accepts 7, 07:30, 7:30, 7:30 AM, 7pm, 19:00
  if ("$t".Trim() -match '^(\d{1,2})(?::(\d{2}))?\s*([aApP][mM])?$') {
    $hh = [int]$Matches[1]; $mm = if ($Matches[2]) { [int]$Matches[2] } else { 0 }; $ap = "$($Matches[3])".ToLower()
    if ($ap -eq "pm" -and $hh -lt 12) { $hh += 12 } elseif ($ap -eq "am" -and $hh -eq 12) { $hh = 0 }
    if ($hh -le 23 -and $mm -le 59 -and (-not $ap -or [int]$Matches[1] -in 1..12)) { $StartTime = "{0:D2}:{1:D2}" -f $hh, $mm; break }
  }
  Say "  Please type a time like 07:30 or 7:30 AM." Yellow
}
while ($true) {
  $hrs = Ask "How many hours should the dashboard stay on?" $(if ($Old) { $Old.schedule.hoursOn } else { 3 })
  $h = 0.0; if ([double]::TryParse("$hrs", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$h) -and $h -gt 0 -and $h -le 12) { $HoursOn = $h; break }
  Say "  Please type a number of hours from 0.5 to 12." Yellow
}
$Days = if (YesNo "Every day? (No = weekdays only)" $(if ($Old) { $Old.schedule.days -ne "weekdays" } else { $true })) { "daily" } else { "weekdays" }

# ------------------------------------------------------------------------------------------
# 5. Optional: calendar and news
# ------------------------------------------------------------------------------------------
Title "5. Your calendar (optional)"
$CalFile = Join-Path $Dir "calendar-link.txt"
$hasCal = (Test-Path $CalFile) -and ((Get-Content $CalFile) -match '^https://')
Say "Paste your calendar's SECRET iCal link (see README: 'Getting your calendar link')."
Say "It's saved only in calendar-link.txt on this PC. Press Enter to skip$(if ($hasCal) { ' and keep the link you already saved' })."
$cal = Read-Host "Secret iCal link"
if ($cal) { $cal = $cal.Trim() -replace '^webcal://', 'https://' }
if ($cal -and $cal.Trim() -match '^https://') {
  @("# Secret iCal link(s) for the dashboard, one per line. Keep this file private.", $cal.Trim()) | Set-Content $CalFile -Encoding UTF8
  Say "  Saved." Green
} elseif ($cal) { Say "  That doesn't start with https:// - skipped." Yellow }

Title "6. Spoken news briefing (optional)"
Say "Press Ctrl+Alt+N for a short news briefing read aloud. It uses YOUR OWN Claude Console API key,"
Say "and each briefing is billed to your account (about 7-9 US cents each). See README for how to get a key."
$KeyFile = Join-Path $Dir "claude-api-key.txt"
$hasKey = (Test-Path $KeyFile) -and ((Get-Content $KeyFile) -match '^sk-ant-')
$Voice = if ($Old -and $Old.news.voice) { $Old.news.voice } else { "Andrew" }
if (YesNo "Set up the news briefing$(if ($hasKey) { ' (a key is already saved)' })?" (-not $hasKey)) {
  $sec = Read-Host "Paste your API key (starts with sk-ant-; it won't be shown)" -AsSecureString
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  if ($plain -and $plain.Trim() -match '^sk-ant-') {
    @("# Claude Console API key for the news briefing. Keep this file private.", $plain.Trim()) | Set-Content $KeyFile -Encoding UTF8
    Say "  Saved to claude-api-key.txt." Green
  } elseif ($plain) { Say "  That doesn't look like a Claude API key (should start with sk-ant-). Skipped." Yellow }
  $plain = $null
  $Voice = Ask "News voice (Andrew, Aria, Jenny, Guy, Ava, Emma, Brian, Michelle...)" $Voice
}

# ------------------------------------------------------------------------------------------
# 7. Save config.json
# ------------------------------------------------------------------------------------------
$Config = [ordered]@{
  tv                 = [ordered]@{ ip = $TvIp; hdmiInput = $Hdmi; soundDevice = $SoundDevice }
  pcHasOwnMonitor    = $OwnMonitor
  location           = $Location
  units              = $Units
  schedule           = [ordered]@{ startTime = $StartTime; days = $Days; hoursOn = $HoursOn }
  news               = [ordered]@{
                         voice = $Voice
                         rate = $(if ($Old -and $Old.news.rate) { $Old.news.rate } else { 1.0 })
                         model = $(if ($Old -and $Old.news.model) { $Old.news.model } else { "claude-haiku-5-5" })
                         maxSearches = $(if ($Old -and $Old.news.maxSearches) { $Old.news.maxSearches } else { 6 }) }
  dataRefreshMinutes = $(if ($Old -and $Old.dataRefreshMinutes) { $Old.dataRefreshMinutes } else { 5 })
}
[IO.File]::WriteAllText($ConfigPath, ($Config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
. (Join-Path $Dir "common.ps1")
Write-ConfigJs (Get-DashConfig)
Title "Saved your settings to config.json"

# ------------------------------------------------------------------------------------------
# 8. Daily schedule (Task Scheduler) and keyboard shortcuts
# ------------------------------------------------------------------------------------------
$On  = [datetime]::ParseExact($StartTime, "HH:mm", [Globalization.CultureInfo]::InvariantCulture)
$Off = $On.AddHours($HoursOn)
$Me  = "$env:USERDOMAIN\$env:USERNAME"
$Principal = New-ScheduledTaskPrincipal -UserId $Me -LogonType Interactive
$Settings  = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
               -ExecutionTimeLimit (New-TimeSpan -Hours ([Math]::Ceiling($HoursOn) + 2))
function Add-DashTask([string]$Name, [string]$Script, [datetime]$At) {
  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $Dir $Script)`""
  $trigger = if ($Days -eq "weekdays") { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At $At }
             else { New-ScheduledTaskTrigger -Daily -At $At }
  Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Principal $Principal -Settings $Settings -Force -ErrorAction Stop | Out-Null
}
try {
  Add-DashTask "Morning Dashboard - TV on"  "start.ps1" $On
  Add-DashTask "Morning Dashboard - TV off" "stop.ps1"  $Off
  Say ("Scheduled: TV on at {0}, off at {1}, {2}." -f $On.ToString("h:mm tt"), $Off.ToString("h:mm tt"), $(if ($Days -eq "daily") { "every day" } else { "Monday to Friday" })) Green
} catch {
  Say "Couldn't create the scheduled tasks: $($_.Exception.Message)" Yellow
  Say "If older 'Morning Dashboard' tasks exist from another setup, delete them in Task Scheduler (or run uninstall.ps1) and run this again." Yellow
}

$Desktop = [Environment]::GetFolderPath("Desktop")
$Shell = New-Object -ComObject WScript.Shell
$Shortcuts = @(
  @{ Name = "Dashboard On (Ctrl+Alt+D)";  Script = "start.ps1";     Key = "CTRL+ALT+D"; Icon = 101 },
  @{ Name = "Dashboard Off (Ctrl+Alt+X)"; Script = "stop.ps1";      Key = "CTRL+ALT+X"; Icon = 100 },
  @{ Name = "News Debrief (Ctrl+Alt+N)";  Script = "news.ps1";      Key = "CTRL+ALT+N"; Icon = 101 },
  @{ Name = "Stop News (Ctrl+Alt+S)";     Script = "news-stop.ps1"; Key = "CTRL+ALT+S"; Icon = 100 })
foreach ($s in $Shortcuts) {
  try {
    $lnk = $Shell.CreateShortcut((Join-Path $Desktop ($s.Name + ".lnk")))
    $lnk.TargetPath  = "powershell.exe"
    $lnk.Arguments   = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $Dir $s.Script)`""
    $lnk.WindowStyle = 7
    $lnk.IconLocation = "$env:SystemRoot\System32\imageres.dll,$($s.Icon)"
    $lnk.Save()
  } catch { Say "Couldn't create shortcut '$($s.Name)': $($_.Exception.Message)" Yellow }
}
# The keyboard shortcuts come from a small background listener (hotkeys.ps1) that starts at every sign-in.
try {
  $hkAction  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $Dir 'hotkeys.ps1')`""
  $hkTrigger = New-ScheduledTaskTrigger -AtLogOn -User $Me
  $hkSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew `
                  -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName "Morning Dashboard - shortcuts" -Action $hkAction -Trigger $hkTrigger -Principal $Principal -Settings $hkSettings -Force -ErrorAction Stop | Out-Null
  Stop-ProcessByCommandLine "powershell.exe" (Join-Path $Dir "hotkeys.ps1")
  Start-Sleep 1
  Start-ScheduledTask -TaskName "Morning Dashboard - shortcuts"
} catch { Say "Couldn't set up the keyboard shortcuts: $($_.Exception.Message)" Yellow }
Say "Keyboard shortcuts ready (they work from anywhere; the desktop icons do the same thing):" Green
Say "  Ctrl+Alt+D  dashboard on      Ctrl+Alt+X  dashboard off"
Say "  Ctrl+Alt+N  news briefing     Ctrl+Alt+S  stop the news"

# ------------------------------------------------------------------------------------------
# 9. Wake from sleep (needs administrator permission once)
# ------------------------------------------------------------------------------------------
Title "Waking the PC in the morning"
Say "Windows can wake the PC from Sleep for the morning start (not from Shut down)."
Say "Allowing that needs administrator permission once; Windows will ask."
$mouse = YesNo "Does your mouse sometimes wake the PC by accident? (we can stop mice from waking it; the keyboard still works)" $false
try {
  $adminArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -AdminStep" + $(if ($mouse) { " -DisableMouseWake" } else { "" })
  Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList $adminArgs
  Say "Done. At night, use Start > Power > Sleep (not Shut down)." Green
} catch {
  Say "Skipped (permission was declined). The morning start still works if the PC is already awake." Yellow
}

Title "Don't ask for a sign-in after sleep"
Say "If Windows asks for your PIN/password when it wakes up, the dashboard waits behind the lock screen"
Say "until you sign in, so the TV won't show it by itself in the morning. To fix that:"
Say "  Settings > Accounts > Sign-in options > 'If you've been away, when should Windows require you"
Say "  to sign in again?' > Never.  (Greyed out? First turn off 'For improved security, only allow"
Say "  Windows Hello sign-in' on the same page. Also turn off Dynamic lock if you use it.)"
Say "Your password is still needed after a restart. Anyone who wakes the PC can use it without one." Yellow
if (YesNo "Open that Settings page now?" $true) {
  Start-Process "ms-settings:signinoptions"
  Read-Host "Change the setting, then press Enter here to continue"
}

# ------------------------------------------------------------------------------------------
# 10. Test
# ------------------------------------------------------------------------------------------
Title "All set"
if (YesNo "Run a 1-minute test now? (TV turns on with the dashboard, then everything goes back to normal)" $true) {
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Dir 'start.ps1')`""
  for ($s = 75; $s -gt 0; $s -= 5) { Write-Host -NoNewline "`r  Test running... $s seconds left  "; Start-Sleep 5 }
  Write-Host ""
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir "stop.ps1")
  Say "Test finished. If the TV showed the dashboard, you're done. If not, see Troubleshooting in README.md" Green
  Say "(the files refresh-log.txt and audio-log.txt in this folder show what happened)."
}
Say ""
Say "To change anything later, run install again. To remove the schedule and shortcuts, run uninstall."
Read-Host "Press Enter to close"
