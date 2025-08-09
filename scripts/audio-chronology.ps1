param(
  [string]$AudioLogDir = './04-logs/audio',
  [string]$OutCsv = './04-logs/audio-chronology.csv'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EvidenceBucketFromAudio([string]$audioPath){
  try {
    $rawRoot = (Resolve-Path -Path './02-evidence/raw').Path
    $full = (Resolve-Path -Path $audioPath).Path
    if($full.StartsWith($rawRoot,[System.StringComparison]::OrdinalIgnoreCase)){
      $rel = $full.Substring($rawRoot.Length) -replace '^[\\/]+',''
      $parts = $rel -split '[\\/]'
      if($parts.Length -ge 1 -and $parts[0]){ return $parts[0] }
    }
  } catch { }
  return ''
}

function Load-Manifests([string]$dir){
  $rows = @()
  $manifests = Get-ChildItem -Path $dir -Recurse -Filter audio-manifest.csv -File -ErrorAction SilentlyContinue
  foreach($m in $manifests){
    $rows += (Import-Csv -Path $m.FullName)
  }
  return $rows
}

function Build-AudioChronology([string]$dir){
  $rows = @()
  $mrows = Load-Manifests -dir $dir
  foreach($r in $mrows){
    $txt = $r.TranscriptTxt
    $content = if(Test-Path $txt){ Get-Content -Path $txt -Raw -ErrorAction SilentlyContinue } else { '' }
    $when = if($r.LastWriteTime){ [datetime]::Parse($r.LastWriteTime) } else { Get-Date }
    $bucket = Get-EvidenceBucketFromAudio $r.AudioPath
    $rows += [pscustomobject]@{
      When = $when.ToString('yyyy-MM-dd HH:mm:ss')
      Source = 'Audio'
      EvidenceBucket = $bucket
      FilePath = $r.AudioPath
      SHA256 = ''
      Title = [IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $r.AudioPath))
      Body = if([string]::IsNullOrWhiteSpace($content)) { '' } else { $content.Substring(0, [Math]::Min(400, $content.Length)) }
      EvidenceRefs = ''
      IncludeHits = ''
      ExcludeHits = ''
      ConcernFlag = ''
    }
  }
  return ($rows | Sort-Object When)
}

$rows = Build-AudioChronology -dir $AudioLogDir
$rows | Export-Csv -NoTypeInformation -Path $OutCsv
Write-Output ("Wrote audio chronology → {0}" -f $OutCsv)


