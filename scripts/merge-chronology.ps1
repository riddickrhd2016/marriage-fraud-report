param(
  [string]$ScreenshotChronoCsv = './04-logs/screenshots-chronology.csv',
  [string]$TranscriptChronoCsv = './04-logs/transcript-chronology.csv',
  [string]$OutCsv = './04-logs/master-chronology.csv'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-OptionalCsv([string]$path){
  if(Test-Path $path){ return Import-Csv -Path $path }
  else { return @() }
}

$snap = Import-OptionalCsv $ScreenshotChronoCsv
$trans = Import-OptionalCsv $TranscriptChronoCsv

$unified = @()

foreach($r in $snap){
  $when = [datetime]::Parse($r.When)
  $unified += [pscustomobject]@{
    When = $when
    Source = "Screenshot ($($r.Source))"
    EvidenceBucket = $r.EvidenceBucket
    FilePath = $r.FilePath
    SHA256 = $r.SHA256
    Title = ''
    Body = ''
    EvidenceRefs = ''
    IncludeHits = $r.IncludeHits
    ExcludeHits = $r.ExcludeHits
    ConcernFlag = $r.ConcernFlag
  }
}

foreach($r in $trans){
  $when = [datetime]::Parse($r.When)
  $unified += [pscustomobject]@{
    When = $when
    Source = 'Transcript'
    EvidenceBucket = ''
    FilePath = ''
    SHA256 = ''
    Title = $r.Title
    Body = $r.Body
    EvidenceRefs = $r.EvidenceRefs
    IncludeHits = ''
    ExcludeHits = ''
    ConcernFlag = ''
  }
}

$unified | Sort-Object When | ForEach-Object {
  $_.When = $_.When.ToString('yyyy-MM-dd HH:mm:ss')
  $_
} | Export-Csv -NoTypeInformation -Path $OutCsv

Write-Output ("Master chronology entries: {0} → {1}" -f $unified.Count, $OutCsv)
