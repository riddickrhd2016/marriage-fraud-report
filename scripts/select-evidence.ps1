param(
  [string]$OcrCsv = './04-logs/screenshots-ocr.csv',
  [string]$OutDir = './02-evidence/redacted/E-001-GooglePhotos-selected',
  [int]$MinIncludeHits = 1,
  [switch]$ExcludeConcern,
  [string]$ManifestCsv = './04-logs/selection-manifest.csv',
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

if(-not (Test-Path $OcrCsv)){
  throw "OCR index not found: $OcrCsv"
}

$rows = Import-Csv -Path $OcrCsv

# Filter by IncludeHits and ConcernFlag
$filtered = $rows | Where-Object {
  ([int]$_.IncludeHits) -ge $MinIncludeHits -and (
    -not $ExcludeConcern -or ($_.ConcernFlag -eq $false -or [string]::Equals([string]$_.ConcernFlag,'False',[System.StringComparison]::OrdinalIgnoreCase))
  )
}

# Deduplicate by SHA256
$byHash = $filtered | Group-Object -Property SHA256 | ForEach-Object { $_.Group | Select-Object -First 1 }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$manifest = @()
$i = 0
foreach($r in $byHash){
  $i++
  $src = $r.FilePath
  if(-not (Test-Path $src)){
    Write-Info "Missing source: $src"
    continue
  }
  $dest = Join-Path $OutDir $r.FileName
  Copy-Item -Force -Path $src -Destination $dest
  $manifest += [pscustomobject]@{
    SHA256 = $r.SHA256
    SourcePath = $src
    DestPath = $dest
    EvidenceBucket = $r.EvidenceBucket
    DateTaken = $r.DateTaken
    FallbackTimestamp = $r.FallbackTimestamp
    IncludeHits = $r.IncludeHits
    ExcludeHits = $r.ExcludeHits
    ConcernFlag = $r.ConcernFlag
  }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ManifestCsv) | Out-Null
$manifest | Export-Csv -NoTypeInformation -Path $ManifestCsv

Write-Output ("Selected {0} of {1} OCR rows → {2}" -f $manifest.Count, $rows.Count, $OutDir)
Write-Output ("Manifest: {0}" -f $ManifestCsv)


