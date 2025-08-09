param(
  [string]$OcrCsv = './04-logs/screenshots-ocr.csv',
  [string]$OutRoot = './02-evidence/redacted/categorized',
  [switch]$SelectedOnly,  # if set, only categorize files present in E-001-GooglePhotos-selected
  [string]$SelectedDir = './02-evidence/redacted/E-001-GooglePhotos-selected',
  [string]$ManifestCsv = './04-logs/categorization-manifest.csv',
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

if(-not (Test-Path $OcrCsv)){
  throw "OCR CSV not found: $OcrCsv"
}

$rows = Import-Csv -Path $OcrCsv

if($SelectedOnly){
  if(-not (Test-Path $SelectedDir)){ throw "SelectedDir not found: $SelectedDir" }
  $selNames = @{}
  Get-ChildItem -Path $SelectedDir -File -ErrorAction SilentlyContinue | ForEach-Object { $selNames[$_.Name.ToLowerInvariant()] = $true }
  $rows = $rows | Where-Object { $selNames.ContainsKey($_.FileName.ToLowerInvariant()) }
}

# Category regexes
$rxFakeId = @('driver','license','dl#','id card','identification','passport','dob','expires','issue','class [a-z0-9]+','state id')
$rxDrugPay = @('cash app','zelle','venmo','western union','receipt','payment','transaction','paid','transfer')
$rxLocation = @('google maps','apple maps','map data','directions','eta','mi','miles','min','street','ave','st\b','lake','phalen','location')
$rxBackground = @('background check','alias','aka','employment','application','e-verify','i-9','ssn')

function Count-Hits([string]$text, [string[]]$patterns){
  if([string]::IsNullOrWhiteSpace($text)){ return 0 }
  $hits = 0
  foreach($p in $patterns){ if([regex]::IsMatch($text, [regex]::Escape($p), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)){ $hits++ } }
  return $hits
}

function Choose-Category($row){
  $text = ''
  try { $text = Get-Content -Path $row.OcrTextPath -Raw -ErrorAction SilentlyContinue } catch { $text = '' }
  $cFake = Count-Hits $text $rxFakeId
  $cDrug = Count-Hits $text $rxDrugPay
  $cLoc = Count-Hits $text $rxLocation
  $cBg = Count-Hits $text $rxBackground
  $scores = [ordered]@{ FakeIDs = $cFake; DrugPayments = $cDrug; LocationScreenshots = $cLoc; BackgroundDocs = $cBg; Conversations = 0 }
  $best = ($scores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
  if($best.Value -gt 0){ return $best.Key }
  return 'Conversations'
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$manifest = @()
$i = 0
foreach($r in ($rows | Sort-Object EvidenceBucket, DateTaken, FallbackTimestamp, FileName)){
  $i++
  if(($i % 50) -eq 0){ Write-Info ("Categorizing {0}/{1}" -f $i, $rows.Count) }
  $category = Choose-Category $r
  $dt = if(-not [string]::IsNullOrWhiteSpace($r.DateTaken)){ [datetime]::Parse($r.DateTaken) } else { [datetime]::Parse($r.FallbackTimestamp) }
  $dateFolder = $dt.ToString('yyyy-MM-dd')
  $destDir = Join-Path (Join-Path $OutRoot $category) $dateFolder
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $destPath = Join-Path $destDir $r.FileName
  if(Test-Path $r.FilePath){ Copy-Item -Force -Path $r.FilePath -Destination $destPath }
  $manifest += [pscustomobject]@{
    SHA256 = $r.SHA256
    Category = $category
    DateFolder = $dateFolder
    SourcePath = $r.FilePath
    DestPath = $destPath
    EvidenceBucket = $r.EvidenceBucket
    DateTaken = $r.DateTaken
    FallbackTimestamp = $r.FallbackTimestamp
  }
}

$manifest | Export-Csv -NoTypeInformation -Path $ManifestCsv
Write-Output ("Categorized {0} screenshot(s) → {1}" -f $rows.Count, $OutRoot)
Write-Output ("Manifest: {0}" -f $ManifestCsv)


