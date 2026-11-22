# Morning Dashboard - news debrief (press Ctrl+Alt+N)
# Asks Claude (with web search) for a short briefing; the dashboard shows it and reads it aloud.
# Uses the Claude Console API key saved in claude-api-key.txt. Never logs the key.
. (Join-Path $PSScriptRoot "common.ps1")
$Config = Get-DashConfig
$Out   = Join-Path $Dir "news-data.js"
$Log   = Join-Path $Dir "news-log.txt"
$Model = if ($Config.news.model) { $Config.news.model } else { "claude-haiku-5-5" }
$MaxSearches = if ($Config.news.maxSearches) { [int]$Config.news.maxSearches } else { 6 }
$Loc = $Config.location
$Place = (@($Loc.city, $Loc.region) | Where-Object { $_ }) -join ", "

function Log($m) { "$(Get-Date -Format 's')  $m" | Add-Content $Log }
$Data = @{}
function Save-News { $json = $Data | ConvertTo-Json -Depth 8 -Compress
  [IO.File]::WriteAllText($Out, "window.NEWS_DATA = $json;", (New-Object Text.UTF8Encoding $false)) }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 200kb) { Remove-Item $Log -Force }

# one briefing at a time
$mutex = New-Object Threading.Mutex($false, "MorningDashboardNews")
$got = $false
try { $got = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }   # previous briefing was stopped
if (-not $got) { exit 0 }

$Data.id = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
$Data.status = "loading"; $Data.message = "Gathering today's news..."; $Data.speaking = -1
Save-News

# make sure the dashboard is on screen (turns the TV on if needed)
$open = Get-ProcessByCommandLine "msedge.exe" (Join-Path $Dir "edge-profile")
if (-not $open) {
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Dir 'start.ps1')`""
}

function Fail($msg, $logmsg) { $Data.status = "error"; $Data.message = $msg; Save-News; Log $logmsg; $mutex.ReleaseMutex(); exit 1 }

$keyFile = Join-Path $Dir "claude-api-key.txt"
$key = $null
if (Test-Path $keyFile) { $key = Get-Content $keyFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^sk-ant-' } | Select-Object -First 1 }
if (-not $key) { Fail "Add your Claude Console API key to claude-api-key.txt in the dashboard folder (or run install.ps1 again)." "no API key in claude-api-key.txt" }

$histFile = Join-Path $Dir "news-history.txt"
$recent = @(); if (Test-Path $histFile) { $recent = @(Get-Content $histFile | Select-Object -Last 40) }
$today = Get-Date -Format "dddd, MMMM d, yyyy"

$system = @"
You are a news editor preparing a short spoken morning briefing for one listener who lives in $Place ($($Loc.country)). Today is $today.
Search the web for the most important news from roughly the last 24 hours, then write the briefing.
Sections, in this order:
- "National": 2 to 3 of the most important national stories for someone living in $($Loc.country).
- "World": 2 to 3 of the most important international stories.
- "Tech": 2 to 3 notable technology stories (AI, big tech, startups, chips, enterprise software).
- "Local": 0 to 2 stories about $Place and the surrounding area, ONLY if genuinely worth knowing today (major public-safety events, serious weather, big transit or road disruptions, major local business or policy news). If nothing local clears that bar, include no Local items.
At most 9 stories in total. Rules: factual and neutral, no opinions. Each summary is 1 or 2 short plain sentences (under 35 words) that are easy to listen to (no URLs, no abbreviations that sound odd aloud). Name the outlet you relied on.
Avoid repeating these recently shown headlines unless there is a major new development:
$($recent -join "`n")
Do not write any commentary between searches. When you are done searching, respond with ONLY a JSON object and no other text, in exactly this shape:
{"intro":"one friendly spoken sentence","items":[{"section":"National","headline":"short headline","summary":"1-2 sentences","source":"Outlet name"}],"outro":"one short spoken closing sentence"}
"@

$tools = @(@{ type = "web_search_20250305"; name = "web_search"; max_uses = $MaxSearches
              user_location = @{ type = "approximate"; city = "$($Loc.city)"; region = "$($Loc.region)"; country = "$($Loc.country)"; timezone = "$($Loc.timeZone)" } })
$messages = @(@{ role = "user"; content = "Prepare today's briefing." })
$text = ""
$cost = 0.0
for ($round = 0; $round -lt 4; $round++) {
  $body = @{ model = $Model; max_tokens = 8000; system = $system; messages = $messages; tools = $tools } | ConvertTo-Json -Depth 30
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "https://api.anthropic.com/v1/messages" -TimeoutSec 240 `
            -Headers @{ "x-api-key" = $key; "anthropic-version" = "2023-06-01" } -ContentType "application/json" `
            -Body ([Text.Encoding]::UTF8.GetBytes($body))
    $r = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
  } catch {
    $detail = $_.Exception.Message
    try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $detail += " | " + $sr.ReadToEnd() } catch {}
    Fail "Couldn't get the news right now. Try again in a minute." "API error: $detail"
  }
  $text += (@($r.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join "")
  # estimated cost: Claude Haiku 5.5 list prices (per million tokens) + web search at $10 per 1,000 searches
  $in = [double]$r.usage.input_tokens; $outT = [double]$r.usage.output_tokens; $srch = [double]$r.usage.server_tool_use.web_search_requests
  if ($in -gt 100000) { $pi = 0.50; $po = 2.50 } else { $pi = 0.10; $po = 0.50 }
  $cost += $in / 1e6 * $pi + $outT / 1e6 * $po + $srch * 0.01
  Log "round $round  stop=$($r.stop_reason)  input_tokens=$($r.usage.input_tokens)  output_tokens=$($r.usage.output_tokens)  searches=$($r.usage.server_tool_use.web_search_requests)"
  if ($r.stop_reason -ne "pause_turn") { break }
  $messages += @{ role = "assistant"; content = $r.content }
}

$s = $text.IndexOf("{"); $e = $text.LastIndexOf("}")
if ($s -lt 0 -or $e -le $s) { Fail "Couldn't put the briefing together. Try again in a minute." "no JSON in reply: $($text.Substring(0, [Math]::Min(300, $text.Length)))" }
try { $brief = $text.Substring($s, $e - $s + 1) | ConvertFrom-Json } catch { Fail "Couldn't put the briefing together. Try again in a minute." "bad JSON: $($_.Exception.Message)" }
$items = @($brief.items)
if ($items.Count -eq 0) { Fail "No stories came back. Try again in a minute." "reply had no items" }

$costFile = Join-Path $Dir "news-costs.csv"
if (-not (Test-Path $costFile)) { "date,cost_usd" | Set-Content $costFile }
"$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$([Math]::Round($cost,4))" | Add-Content $costFile
$month = Get-Date -Format "yyyy-MM"
$monthTotal = (Import-Csv $costFile | Where-Object { $_.date -like "$month*" } | Measure-Object -Property cost_usd -Sum).Sum
$allTotal = (Import-Csv $costFile | Measure-Object -Property cost_usd -Sum).Sum
$Data.cost = [Math]::Round($cost, 3); $Data.monthTotal = [Math]::Round($monthTotal, 2); $Data.allTotal = [Math]::Round($allTotal, 2)
$Data.status = "ready"; $Data.intro = $brief.intro; $Data.outro = $brief.outro; $Data.items = $items
$Data.created = (Get-Date -Format "h:mm tt"); $Data.message = ""
Save-News
$items | ForEach-Object { "$(Get-Date -Format 'yyyy-MM-dd')  [$($_.section)] $($_.headline)" } | Add-Content $histFile
Log "briefing ready: $($items.Count) stories, est. cost `$$([Math]::Round($cost,3)), this month `$$([Math]::Round($monthTotal,2))"

# The dashboard page reads the briefing aloud (Microsoft Edge natural voice) and highlights each story.
$mutex.ReleaseMutex()
