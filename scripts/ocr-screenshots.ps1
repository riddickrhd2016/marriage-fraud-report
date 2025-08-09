param(
  [string]$ScanRoot = './02-evidence/raw',
  [string]$OutDir = './04-logs/ocr',
  [string]$OcrIndexCsv = './04-logs/screenshots-ocr.csv',
  [string]$ChronologyCsv = './04-logs/screenshots-chronology.csv',
  [string[]]$IncludeKeywords = @(),
  [string[]]$ExcludeKeywords = @(),
  [string]$Language = 'eng',
  [int]$PreviewChars = 400,
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

function Resolve-TesseractPath(){
  $cmd = Get-Command tesseract -ErrorAction SilentlyContinue
  if($cmd){ return $cmd.Source }
  $default = 'C:\Program Files\Tesseract-OCR\tesseract.exe'
  if(Test-Path $default){ return $default }
  throw "tesseract.exe not found. Install Tesseract OCR and ensure it's in PATH or at 'C:\\Program Files\\Tesseract-OCR\\tesseract.exe'"
}

function Get-ExifDateTimeOrNull([string]$filePath){
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null
    $img = [System.Drawing.Image]::FromFile($filePath)
    try {
      # EXIF DateTimeOriginal = 0x9003, fallback to 0x0132 (DateTime)
      $prop = $img.PropertyItems | Where-Object { $_.Id -in 0x9003, 0x0132 } | Select-Object -First 1
      if($null -ne $prop){
        $raw = [System.Text.Encoding]::ASCII.GetString($prop.Value).Trim([char]0)
        $normalized = $raw -replace ':','-',1 -replace ':','-',1
        $dt = [datetime]::Parse($normalized)
        return $dt
      }
    } finally {
      $img.Dispose()
    }
  } catch { }
  return $null
}

function Get-GoogleSidecarDateOrNull([IO.FileInfo]$file){
  try {
    $dir = $file.DirectoryName
    $baseNameOnly = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $matches = Get-ChildItem -Path $dir -Filter "${baseNameOnly}*.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $matches){ return $null }
    $json = Get-Content -Raw -Path $matches.FullName | ConvertFrom-Json
    $ts = $null
    if($json.photoTakenTime -and $json.photoTakenTime.timestamp){ $ts = [double]$json.photoTakenTime.timestamp }
    elseif($json.creationTime -and $json.creationTime.timestamp){ $ts = [double]$json.creationTime.timestamp }
    elseif($json.mediaMetadata -and $json.mediaMetadata.creationTime){ try { return [datetime]$json.mediaMetadata.creationTime } catch { } }
    if($ts){ return [DateTimeOffset]::FromUnixTimeSeconds([long]$ts).LocalDateTime }
  } catch { }
  return $null
}

function Get-ImageFiles([string]$root){
  $imgExts = @('.png','.jpg','.jpeg','.webp','.gif') # HEIC often unsupported without extra codecs
  return Get-ChildItem -Path $root -Recurse -File -ErrorAction Stop | Where-Object { $imgExts -contains $_.Extension.ToLowerInvariant() }
}

function Get-EvidenceBucket([string]$fullPath){
  $rootFull = (Resolve-Path -Path $ScanRoot).Path
  $normalized = (Resolve-Path -Path $fullPath).Path
  if($normalized.StartsWith($rootFull,[System.StringComparison]::OrdinalIgnoreCase)){
    $relative = $normalized.Substring($rootFull.Length) -replace '^[\\/]+',''
    $parts = $relative -split '[\\/]'
    if($parts.Length -ge 1 -and $parts[0]){ return $parts[0] }
  }
  return ''
}

Write-Info "Locating Tesseract..."
$tess = Resolve-TesseractPath
Write-Info "Using: $tess"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$files = Get-ImageFiles -root $ScanRoot | Sort-Object FullName

$ocrRows = @()
$chronoRows = @()
$includeRegexes = $IncludeKeywords | ForEach-Object { [regex]::new([regex]::Escape($_), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
$excludeRegexes = $ExcludeKeywords | ForEach-Object { [regex]::new([regex]::Escape($_), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }

$i = 0
foreach($f in $files){
  $i++
  if(($i % 30) -eq 0){ Write-Info ("OCR {0}/{1}: {2}" -f $i, $files.Count, $f.Name) }

  $sha = (Get-FileHash -Algorithm SHA256 -Path $f.FullName).Hash
  $txtPath = Join-Path $OutDir ($sha + '.txt')
  if(-not (Test-Path $txtPath)){
    # Run OCR
    & $tess $f.FullName stdout -l $Language 2>$null | Out-File -Encoding UTF8 $txtPath
  }
  $text = (Get-Content -Path $txtPath -Raw -ErrorAction SilentlyContinue)
  if($null -eq $text){ $text = '' }

  $incHits = 0
  foreach($rx in $includeRegexes){ if($rx.IsMatch($text)){ $incHits++ } }
  $excHits = 0
  foreach($rx in $excludeRegexes){ if($rx.IsMatch($text)){ $excHits++ } }
  $concern = $excHits -gt 0

  $dateTaken = Get-ExifDateTimeOrNull $f.FullName
  if(-not $dateTaken){ $dateTaken = Get-GoogleSidecarDateOrNull $f }
  $fallbackTime = $f.LastWriteTime
  $when = if($dateTaken){ $dateTaken } else { $fallbackTime }

  $bucket = Get-EvidenceBucket $f.FullName

  $ocrRows += [pscustomobject]@{
    EvidenceBucket = $bucket
    FilePath = $f.FullName
    FileName = $f.Name
    SHA256 = $sha
    DateTaken = if($dateTaken){ $dateTaken.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    FallbackTimestamp = $fallbackTime.ToString('yyyy-MM-dd HH:mm:ss')
    OcrTextPath = $txtPath
    IncludeHits = $incHits
    ExcludeHits = $excHits
    ConcernFlag = $concern
    OcrPreview = if([string]::IsNullOrWhiteSpace($text)) { '' } else { ($text.Substring(0, [Math]::Min($PreviewChars, $text.Length))).Replace("`r`n"," ").Replace("`n"," ") }
  }

  $chronoRows += [pscustomobject]@{
    EvidenceBucket = $bucket
    FilePath = $f.FullName
    FileName = $f.Name
    SHA256 = $sha
    When = $when.ToString('yyyy-MM-dd HH:mm:ss')
    Source = if($dateTaken){ 'EXIF/Sidecar' } else { 'FileTimestamp' }
    OcrTextPath = $txtPath
    IncludeHits = $incHits
    ExcludeHits = $excHits
    ConcernFlag = $concern
  }
}

# Ensure output directories
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OcrIndexCsv) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ChronologyCsv) | Out-Null

$ocrRows | Sort-Object EvidenceBucket, DateTaken, FallbackTimestamp, FileName | Export-Csv -NoTypeInformation -Path $OcrIndexCsv
$chronoRows | Sort-Object When, FileName | Export-Csv -NoTypeInformation -Path $ChronologyCsv

Write-Output ("OCR complete for {0} images." -f $files.Count)
Write-Output ("Index: {0}" -f $OcrIndexCsv)
Write-Output ("Chronology: {0}" -f $ChronologyCsv)


