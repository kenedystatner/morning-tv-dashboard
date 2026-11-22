# Morning TV Dashboard - uninstaller
# Removes the daily scheduled tasks and the desktop shortcuts. Your files in this folder are left alone;
# delete the folder yourself if you want everything gone.
$Removed = 0
foreach ($t in "Morning Dashboard - TV on", "Morning Dashboard - TV off") {
  try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop; Write-Host "Removed scheduled task: $t" -ForegroundColor Green; $Removed++ }
  catch { Write-Host "No scheduled task named '$t' (or no permission to remove it)." }
}
$Desktop = [Environment]::GetFolderPath("Desktop")
foreach ($n in "Dashboard On (Ctrl+Alt+D)", "Dashboard Off (Ctrl+Alt+X)", "News Debrief (Ctrl+Alt+N)", "Stop News (Ctrl+Alt+S)") {
  $p = Join-Path $Desktop "$n.lnk"
  if (Test-Path $p) { Remove-Item $p -Force; Write-Host "Removed shortcut: $n" -ForegroundColor Green; $Removed++ }
}
Write-Host ""
Write-Host "Done ($Removed items removed). Windows' 'allow wake timers' power setting was left on;"
Write-Host "it's harmless, but you can turn it off in Control Panel > Power Options > Change advanced power settings > Sleep."
Write-Host "Your private files (config.json, calendar-link.txt, claude-api-key.txt) are still in this folder - delete the folder to remove them."
Read-Host "Press Enter to close"
