param(
  [string]$TranscriptPath = './02-evidence/raw/E-004-TimelineDocs/Transcript.md',
  [string]$OutCsv = './04-logs/transcript-chronology.csv',
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

if(-not (Test-Path $TranscriptPath)){
  throw "Transcript not found at $TranscriptPath. Copy the template to Transcript.md and fill it in."
}

$rawContent = Get-Content -Path $TranscriptPath -Raw
$lines = $rawContent -split "`r?`n"

$pattern = '^[\[](?<date>\d{4}-\d{2}-\d{2})(?:[ T](?<time>\d{2}:\d{2})(?::\d{2})?)?[\]]\s*(?<summary>.*)$'

$entries = @()
$current = $null

for($i=0; $i -lt $lines.Count; $i++){
  $line = $lines[$i].TrimEnd()
  if([string]::IsNullOrWhiteSpace($line)){
    if($current -ne $null){ $current.Body += "`n" }
    continue
  }
  $m = [regex]::Match($line, $pattern)
  if($m.Success){
    if($current -ne $null){ $entries += $current }
    $dateStr = $m.Groups['date'].Value
    $timeStr = $m.Groups['time'].Value
    if([string]::IsNullOrWhiteSpace($timeStr)){ $timeStr = '00:00' }
    $dt = [datetime]::ParseExact("$dateStr $timeStr", 'yyyy-MM-dd HH:mm', $null)
    $summary = $m.Groups['summary'].Value.Trim()
    $current = [pscustomobject]@{
      When = $dt
      Title = $summary
      Body = ''
    }
  } else {
    if($current -eq $null){ continue }
    if([string]::IsNullOrWhiteSpace($current.Body)){ $current.Body = $line } else { $current.Body += "`n$line" }
  }
}
if($current -ne $null){ $entries += $current }

# Extract evidence refs like E-001, E-012
foreach($e in $entries){
  $refs = @()
  if($e.Title){ $refs += ([regex]::Matches($e.Title, 'E-\d{3}')) | ForEach-Object { $_.Value } }
  if($e.Body){ $refs += ([regex]::Matches($e.Body, 'E-\d{3}')) | ForEach-Object { $_.Value } }
  $refs = $refs | Sort-Object -Unique
  $e | Add-Member -NotePropertyName EvidenceRefs -NotePropertyValue ($refs -join '; ')
  $e | Add-Member -NotePropertyName Source -NotePropertyValue 'Transcript'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutCsv) | Out-Null
$entries | Sort-Object When | ForEach-Object {
  $_.When = $_.When.ToString('yyyy-MM-dd HH:mm:ss')
  $_
} | Export-Csv -NoTypeInformation -Path $OutCsv

Write-Output ("Parsed transcript → {0} entries → {1}" -f $entries.Count, $OutCsv)
