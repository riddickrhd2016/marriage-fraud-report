param(
  [string]$ScreensCsv = './04-logs/screenshots-chronology.csv',
  [string]$TranscriptCsv = './04-logs/transcript-chronology.csv',
  [string]$AudioCsv = './04-logs/audio-chronology.csv',
  [string]$DocsCsv = './04-logs/docs-chronology.csv',
  [string]$OutCsv = './04-logs/master-chronology.csv'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-OptionalCsv([string]$p){ if(Test-Path $p){ Import-Csv -Path $p } else { @() } }

$screens = Import-OptionalCsv $ScreensCsv
$trans = Import-OptionalCsv $TranscriptCsv
$audio = Import-OptionalCsv $AudioCsv
$docs = Import-OptionalCsv $DocsCsv

$rows = @()
foreach($r in $screens){ $rows += $r }
foreach($r in $trans){ $rows += $r }
foreach($r in $audio){ $rows += $r }
foreach($r in $docs){ $rows += $r }

$rows | Sort-Object {[datetime]::Parse($_.When)}, FileName | ForEach-Object {
  $_.When = ([datetime]::Parse($_.When)).ToString('yyyy-MM-dd HH:mm:ss')
  $_
} | Export-Csv -NoTypeInformation -Path $OutCsv

Write-Output ("Merged {0} rows → {1}" -f $rows.Count, $OutCsv)


