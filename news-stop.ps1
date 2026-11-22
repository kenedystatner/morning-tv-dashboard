# Stops the news briefing (Ctrl+Alt+S): ends the reading and hides the news panel.
. (Join-Path $PSScriptRoot "common.ps1")
Stop-ProcessByCommandLine "powershell.exe" (Join-Path $Dir "news.ps1")
[IO.File]::WriteAllText((Join-Path $Dir "news-data.js"), 'window.NEWS_DATA = {"id":0,"status":"stopped","doneAt":0};', (New-Object Text.UTF8Encoding $false))
