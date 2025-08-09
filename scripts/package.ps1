param([string]$OutDir = './05-exports',[string]$RedactedDir = './02-evidence/redacted')
$date = Get-Date -Format 'yyyyMMdd-HHmmss'
$zip = Join-Path $OutDir ("submission-" + $date + ".zip")
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$temp = Join-Path $env:TEMP ("submission-" + $date)
New-Item -ItemType Directory -Force -Path $temp | Out-Null
Copy-Item -Recurse -Force './01-report' $temp | Out-Null
Copy-Item -Recurse -Force './03-correspondence' $temp | Out-Null
Copy-Item -Recurse -Force $RedactedDir (Join-Path $temp '02-evidence/redacted') | Out-Null
Copy-Item -Force './04-logs/Evidence-Index.csv' (Join-Path $temp '04-logs/Evidence-Index.csv') | Out-Null
Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zip -Force
Remove-Item -Recurse -Force $temp
Write-Output "Created $zip"
