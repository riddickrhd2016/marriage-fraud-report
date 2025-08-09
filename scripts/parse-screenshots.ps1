param(
  [string]$ScanRoot = './02-evidence/raw',
  [string]$OutCsv = './04-logs/screenshots-index.csv',
  [string]$DuplicatesCsv = './04-logs/screenshots-duplicates.csv',
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

function Get-ExifDateTimeOrNull([string]$filePath){
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null
    $img = [System.Drawing.Image]::FromFile($filePath)
    try {
      # EXIF DateTimeOriginal = 0x9003, fallback to 0x0132 (DateTime)
      $prop = $img.PropertyItems | Where-Object { $_.Id -in 0x9003, 0x0132 } | Select-Object -First 1
      if($null -ne $prop){
        $raw = [System.Text.Encoding]::ASCII.GetString($prop.Value).Trim([char]0)
        # Format usually "YYYY:MM:DD HH:MM:SS"
        $normalized = $raw -replace ':','-',1 -replace ':','-',1
        $dt = [datetime]::Parse($normalized)
        return $dt
      }
    } finally {
      $img.Dispose()
    }
  } catch {
    # Ignore (unsupported format like HEIC/PNG with no EXIF)
  }
  return $null
}

function Get-GoogleSidecarDateOrNull([IO.FileInfo]$file){
  try {
    $dir = $file.DirectoryName
    $base = [IO.Path]::GetFileName($file.Name)
    $candidateExact = Join-Path $dir ($base + '.json')
    $jsonPath = $null
    if(Test-Path $candidateExact){ $jsonPath = $candidateExact }
    if(-not $jsonPath){
      # Try base name match (Google Takeout often uses filename + ".json")
      $baseNameOnly = [IO.Path]::GetFileNameWithoutExtension($file.Name)
      $matches = Get-ChildItem -Path $dir -Filter "${baseNameOnly}*.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if($matches){ $jsonPath = $matches.FullName }
    }
    if(-not $jsonPath){ return $null }
    $json = Get-Content -Raw -Path $jsonPath | ConvertFrom-Json
    # Google Photos JSON patterns
    $ts = $null
    if($json.photoTakenTime -and $json.photoTakenTime.timestamp){ $ts = [double]$json.photoTakenTime.timestamp }
    elseif($json.creationTime -and $json.creationTime.timestamp){ $ts = [double]$json.creationTime.timestamp }
    elseif($json.mediaMetadata -and $json.mediaMetadata.creationTime){
      # Sometimes ISO 8601
      try { return [datetime]$json.mediaMetadata.creationTime } catch { }
    }
    if($ts){ return [DateTimeOffset]::FromUnixTimeSeconds([long]$ts).LocalDateTime }
  } catch {
    # Ignore JSON parse errors
  }
  return $null
}

function Get-EvidenceBucket([string]$fullPath){
  # Extract immediate child directory after ScanRoot, e.g., E-005-LocationScreenshots
  $rootFull = (Resolve-Path -Path $ScanRoot).Path
  $normalized = (Resolve-Path -Path $fullPath).Path
  if($normalized.StartsWith($rootFull,[System.StringComparison]::OrdinalIgnoreCase)){
    $relative = $normalized.Substring($rootFull.Length) -replace '^[\\/]+',''
    $parts = $relative -split '[\\/]'
    if($parts.Length -ge 1 -and $parts[0]){ return $parts[0] }
  }
  return ''
}

Write-Info "Scanning: $ScanRoot"
$imgExts = @('.png','.jpg','.jpeg','.heic','.webp','.gif')
$files = Get-ChildItem -Path $ScanRoot -Recurse -File -ErrorAction Stop |
  Where-Object { $imgExts -contains $_.Extension.ToLowerInvariant() } |
  Sort-Object FullName

$rows = @()
$i = 0
foreach($f in $files){
  $i++
  if(($i % 50) -eq 0){ Write-Info ("Processed {0}/{1}" -f $i, $files.Count) }

  $sha = (Get-FileHash -Algorithm SHA256 -Path $f.FullName).Hash
  $dateTaken = Get-ExifDateTimeOrNull $f.FullName
  if(-not $dateTaken){ $dateTaken = Get-GoogleSidecarDateOrNull $f }
  $fallbackTime = $f.LastWriteTime

  $bucket = Get-EvidenceBucket $f.FullName
  $dtForGrouping = if($dateTaken){ $dateTaken } else { $fallbackTime }
  $yyyy = $dtForGrouping.ToString('yyyy')
  $ymd = $dtForGrouping.ToString('yyyy-MM-dd')
  $proposedRel = if([string]::IsNullOrWhiteSpace($bucket)) { Join-Path $yyyy $ymd } else { Join-Path (Join-Path $bucket $yyyy) $ymd }

  $rows += [pscustomobject]@{
    EvidenceBucket = $bucket
    FilePath = $f.FullName
    FileName = $f.Name
    Extension = $f.Extension.ToLowerInvariant()
    SizeBytes = $f.Length
    SHA256 = $sha
    DateTaken = if($dateTaken){ $dateTaken.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    FallbackTimestamp = $fallbackTime.ToString('yyyy-MM-dd HH:mm:ss')
    ProposedFolder = $proposedRel
  }
}

# Duplicate grouping by SHA256
$dupeGroups = @($rows | Group-Object -Property SHA256 | Where-Object { $_.Count -gt 1 })
$dupLookup = @{}
foreach($g in $dupeGroups){
  $dupLookup[$g.Name] = $true
}

$rowsWithFlags = $rows | ForEach-Object {
  $isDup = $dupLookup.ContainsKey($_.SHA256)
  if($isDup){ $_ | Add-Member -NotePropertyName DuplicateGroupId -NotePropertyValue $_.SHA256 }
  else { $_ | Add-Member -NotePropertyName DuplicateGroupId -NotePropertyValue '' }
  $_
}

# Ensure output directory
$outDir = Split-Path -Parent $OutCsv
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$rowsWithFlags | Sort-Object EvidenceBucket, DateTaken, FallbackTimestamp, FileName | Export-Csv -NoTypeInformation -Path $OutCsv

if($dupeGroups.Length -gt 0){
  $dupRows = foreach($g in $dupeGroups){
    foreach($item in $g.Group){
      [pscustomobject]@{
        SHA256 = $g.Name
        FilePath = $item.FilePath
        EvidenceBucket = $item.EvidenceBucket
        SizeBytes = $item.SizeBytes
        DateTaken = $item.DateTaken
        FallbackTimestamp = $item.FallbackTimestamp
      }
    }
  }
  $dupRows | Export-Csv -NoTypeInformation -Path $DuplicatesCsv
}

Write-Output ("Indexed {0} images → {1}" -f $rows.Count, $OutCsv)
if($dupeGroups.Length -gt 0){ Write-Output ("Detected {0} duplicate group(s) → {1}" -f $dupeGroups.Length, $DuplicatesCsv) }


