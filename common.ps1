# Shared helpers for the Morning TV Dashboard scripts. Every script in this folder
# dot-sources this file, so all settings come from config.json in this same folder.
$Dir = $PSScriptRoot

function Get-DashConfig {
  $p = Join-Path $Dir "config.json"
  if (-not (Test-Path $p)) { throw "config.json is missing. Run install.ps1 first." }
  Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Send a remote-control key to the Roku TV (PowerOn, PowerOff, InputHDMI1...).
function Invoke-Roku([string]$Key) {
  try {
    Invoke-WebRequest -UseBasicParsing -Method Post -TimeoutSec 5 -Uri "http://$($Config.tv.ip):8060/keypress/$Key" | Out-Null
    return $true
  } catch { return $false }
}

# Processes whose command line mentions a given text (e.g. this folder's start.ps1).
function Get-ProcessByCommandLine([string]$Name, [string]$Text) {
  Get-CimInstance Win32_Process -Filter "Name='$Name'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Text, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
}

function Stop-ProcessByCommandLine([string]$Name, [string]$Text) {
  Get-ProcessByCommandLine $Name $Text | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# Writes config.js, the part of config.json the dashboard page needs (no secrets).
function Write-ConfigJs($Cfg) {
  $page = [ordered]@{
    city               = $Cfg.location.city
    latitude           = $Cfg.location.latitude
    longitude          = $Cfg.location.longitude
    timeZone           = $Cfg.location.timeZone
    units              = $Cfg.units
    voice              = $Cfg.news.voice
    voiceRate          = $Cfg.news.rate
    dataRefreshMinutes = $Cfg.dataRefreshMinutes
  }
  $json = $page | ConvertTo-Json -Compress
  [IO.File]::WriteAllText((Join-Path $Dir "config.js"), "window.DASHBOARD_CONFIG = $json;", (New-Object Text.UTF8Encoding $false))
}

function Get-EdgePath {
  @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
}
