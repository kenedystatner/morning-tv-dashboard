# Downloads the weather (Open-Meteo, free, no key) and your calendar (secret iCal link in
# calendar-link.txt) into files the dashboard page reads. Never logs your calendar link.
. (Join-Path $PSScriptRoot "common.ps1")
$Config = Get-DashConfig
$log = Join-Path $Dir "refresh-log.txt"
if ((Test-Path $log) -and (Get-Item $log).Length -gt 100kb) { Remove-Item $log -Force }
function Log($m) { "$(Get-Date -Format 's')  $m" | Add-Content $log }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

Write-ConfigJs $Config

# ---------- weather ----------
$metric = $Config.units -eq "celsius"
$inv = [Globalization.CultureInfo]::InvariantCulture
$params = [ordered]@{
  latitude           = ([double]$Config.location.latitude).ToString($inv)
  longitude          = ([double]$Config.location.longitude).ToString($inv)
  timezone           = [Uri]::EscapeDataString($Config.location.timeZone)
  forecast_days      = "6"
  temperature_unit   = $(if ($metric) { "celsius" } else { "fahrenheit" })
  wind_speed_unit    = $(if ($metric) { "kmh" } else { "mph" })
  precipitation_unit = $(if ($metric) { "mm" } else { "inch" })
  current            = "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m,is_day"
  hourly             = "temperature_2m,precipitation_probability,weather_code,is_day"
  daily              = "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
}
$q = ($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
$weatherUrl = "https://api.open-meteo.com/v1/forecast?$q"
try {
  $tmp = Join-Path $env:TEMP "md-weather.json"
  for ($try = 1; $try -le 3; $try++) {
    try { Invoke-WebRequest -UseBasicParsing -Uri $weatherUrl -OutFile $tmp -TimeoutSec 30; break }
    catch { if ($try -eq 3) { throw }; Start-Sleep 10 }
  }
  $json = Get-Content $tmp -Raw -Encoding UTF8
  Set-Content (Join-Path $Dir "weather-data.js") ("window.WEATHER_DATA = " + $json + ";") -Encoding UTF8
  Log "weather ok"
} catch { Log "weather FAILED: $($_.Exception.Message)" }

# ---------- calendar ----------
$linkFile = Join-Path $Dir "calendar-link.txt"
$links = @()
if (Test-Path $linkFile) { $links = @(Get-Content $linkFile | ForEach-Object { $_.Trim() -replace '^webcal://', 'https://' } | Where-Object { $_ -match '^https://' }) }
if ($links.Count -eq 0) { Log "no calendar link in calendar-link.txt yet"; exit 0 }
$texts = @()
$n = 0
foreach ($l in $links) {
  $n++
  try {
    $tmp = Join-Path $env:TEMP "md-cal.ics"
    Invoke-WebRequest -UseBasicParsing -Uri $l -OutFile $tmp -TimeoutSec 30
    $t = Get-Content $tmp -Raw -Encoding UTF8
    if ($t -notmatch "BEGIN:VCALENDAR") { throw "that link didn't return a calendar (check it's the secret iCal address)" }
    $texts += $t
    Log "calendar $n ok ($([int]((Get-Item $tmp).Length/1kb)) KB)"
  } catch { Log "calendar $n FAILED: $($_.Exception.Message)" }
}
if ($texts.Count) {
  Set-Content (Join-Path $Dir "calendar-data.js") ("window.CALENDAR_ICS = " + (ConvertTo-Json -InputObject ([string[]]@($texts | ForEach-Object { [string]$_ })) -Compress) + ";") -Encoding UTF8
}
