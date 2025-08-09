param(
  [string]$InputTextPath,
  [string]$OutputMarkdownPath = './02-evidence/raw/E-004-TimelineDocs/Transcript.md',
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

if(-not (Test-Path $InputTextPath)){
  throw "Input text not found: $InputTextPath"
}

$rawContent = Get-Content -Path $InputTextPath -Raw
$lines = $rawContent -split "`r?`n"

# Patterns to detect timestamps (common formats):
$patterns = @(
  # [YYYY-MM-DD HH:MM]
  '^[\[]?(?<date>\d{4}-\d{2}-\d{2})(?:[ T](?<time>\d{1,2}:\d{2})(?::\d{2})?)?[\]]?\s*(?<rest>.*)$',
  # MM/DD/YYYY HH:MM AM/PM
  '^(?<md>\d{1,2})/(?<dd>\d{1,2})/(?<yyyy>\d{4})(?:\s+(?<hr>\d{1,2}):(?<min>\d{2})(?:\s*(?<ampm>AM|PM|am|pm))?)?\s*(?<rest>.*)$',
  # Month DD, YYYY HH:MM AM/PM
  '^(?<mon>Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(?<dd>\d{1,2}),\s+(?<yyyy>\d{4})(?:\s+(?<hr>\d{1,2}):(?<min>\d{2})\s*(?<ampm>AM|PM|am|pm)?)?\s*(?<rest>.*)$'
)

function Try-ParseDate([string]$line){
  foreach($pat in $patterns){
    $m = [regex]::Match($line, $pat)
    if(-not $m.Success){ continue }
    if($m.Groups['date'].Success){
      $d = $m.Groups['date'].Value
      $t = if($m.Groups['time'].Success -and $m.Groups['time'].Value){ $m.Groups['time'].Value } else { '00:00' }
      try { return [datetime]::ParseExact("$d $t", @('yyyy-MM-dd HH:mm','yyyy-MM-dd H:mm','yyyy-MM-dd HH:mm:ss','yyyy-MM-dd H:mm:ss'), $null) } catch { }
    } elseif($m.Groups['md'].Success){
      $yyyy = $m.Groups['yyyy'].Value
      $mm = $m.Groups['md'].Value.PadLeft(2,'0')
      $dd = $m.Groups['dd'].Value.PadLeft(2,'0')
      $hr = if($m.Groups['hr'].Success) { [int]$m.Groups['hr'].Value } else { 0 }
      $min = if($m.Groups['min'].Success) { [int]$m.Groups['min'].Value } else { 0 }
      $ampm = if($m.Groups['ampm'].Success) { $m.Groups['ampm'].Value.ToUpperInvariant() } else { '' }
      if($ampm -eq 'PM' -and $hr -lt 12){ $hr += 12 }
      if($ampm -eq 'AM' -and $hr -eq 12){ $hr = 0 }
      return (Get-Date -Year $yyyy -Month $mm -Day $dd -Hour $hr -Minute $min -Second 0)
    } elseif($m.Groups['mon'].Success){
      $monMap = @{ Jan=1; Feb=2; Mar=3; Apr=4; May=5; Jun=6; Jul=7; Aug=8; Sep=9; Oct=10; Nov=11; Dec=12 }
      $yyyy = [int]$m.Groups['yyyy'].Value
      $mm = [int]$monMap[$m.Groups['mon'].Value.Substring(0,3)]
      $dd = [int]$m.Groups['dd'].Value
      $hr = if($m.Groups['hr'].Success) { [int]$m.Groups['hr'].Value } else { 0 }
      $min = if($m.Groups['min'].Success) { [int]$m.Groups['min'].Value } else { 0 }
      $ampm = if($m.Groups['ampm'].Success) { $m.Groups['ampm'].Value.ToUpperInvariant() } else { '' }
      if($ampm -eq 'PM' -and $hr -lt 12){ $hr += 12 }
      if($ampm -eq 'AM' -and $hr -eq 12){ $hr = 0 }
      return (Get-Date -Year $yyyy -Month $mm -Day $dd -Hour $hr -Minute $min -Second 0)
    }
  }
  return $null
}

function Get-Rest([string]$line){
  foreach($pat in $patterns){
    $m = [regex]::Match($line, $pat)
    if($m.Success){
      if($m.Groups['rest'].Success){ return $m.Groups['rest'].Value.Trim() }
      return ''
    }
  }
  return $line
}

$out = @()
$current = $null

for($i=0; $i -lt $lines.Count; $i++){
  $raw = $lines[$i]
  $line = $raw.TrimEnd()
  if([string]::IsNullOrWhiteSpace($line)){
    if($current -ne $null){ $current.Body += "`n" }
    continue
  }
  $dt = Try-ParseDate $line
  if($dt -ne $null){
    if($current -ne $null){ $out += $current }
    $rest = Get-Rest $line
    $current = [pscustomobject]@{
      When = $dt
      Title = if([string]::IsNullOrWhiteSpace($rest)) { '' } else { $rest }
      Body = ''
    }
  } else {
    if($current -eq $null){
      # Start a synthetic entry with unknown time (use previous day if possible)
      $current = [pscustomobject]@{ When = (Get-Date -Date '2000-01-01'); Title = $line; Body = '' }
    } else {
      if([string]::IsNullOrWhiteSpace($current.Body)){ $current.Body = $line } else { $current.Body += "`n$line" }
    }
  }
}
if($current -ne $null){ $out += $current }

$md = @()
foreach($e in ($out | Sort-Object When)){
  $ts = $e.When.ToString('yyyy-MM-dd HH:mm')
  $title = if([string]::IsNullOrWhiteSpace($e.Title)) { '...' } else { $e.Title }
  $md += "[$ts] $title"
  if(-not [string]::IsNullOrWhiteSpace($e.Body)){
    $md += $e.Body
  }
  $md += ''
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputMarkdownPath) | Out-Null
Set-Content -Path $OutputMarkdownPath -Value ($md -join "`r`n") -Encoding UTF8

Write-Info ("Wrote parsed markdown: {0}" -f $OutputMarkdownPath)


