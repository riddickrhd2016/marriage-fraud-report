param(
  [string]$RawDir = './02-evidence/raw',
  [string]$RedactedDir = './02-evidence/redacted',
  [string]$IndexCsv = './04-logs/Evidence-Index.csv',
  [string]$HashCsv = './04-logs/hashes.csv',
  [string]$OutReport = './04-logs/validation-report.md',
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

function Ensure-Directory([string]$path){
  $dir = Split-Path -Parent $path
  if(-not [string]::IsNullOrWhiteSpace($dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
}

function Import-OptionalCsv([string]$path){
  if(Test-Path $path){ return Import-Csv -Path $path }
  else { return @() }
}

Write-Info "Loading inputs..."
$indexRows = Import-OptionalCsv $IndexCsv
$hashRows = Import-OptionalCsv $HashCsv

$now = Get-Date

# Build lookups from hashes.csv if available
$shaToFile = @{}
$fileNameToFiles = @{}
foreach($h in $hashRows){
  if($h.SHA256){ $shaToFile[$h.SHA256] = $h }
  $fn = $h.FileName
  if(-not [string]::IsNullOrWhiteSpace($fn)){
    if(-not $fileNameToFiles.ContainsKey($fn)){ $fileNameToFiles[$fn] = New-Object System.Collections.Generic.List[object] }
    $fileNameToFiles[$fn].Add($h)
  }
}

# If hashes.csv is missing, fall back to scanning raw directory minimally (no hashing)
$rawFiles = @()
if($hashRows.Count -gt 0){
  $rawFiles = $hashRows | ForEach-Object { $_.FilePath }
} elseif(Test-Path $RawDir) {
  $rawFiles = Get-ChildItem -Path $RawDir -Recurse -File | Select-Object -ExpandProperty FullName
}

# Helper: find file existence by FileName using hashes.csv (preferred) or disk search
function Test-FileNameExists([string]$fileName){
  if([string]::IsNullOrWhiteSpace($fileName)){ return $false }
  if($fileNameToFiles.ContainsKey($fileName)){ return $true }
  # Fallback: search disk (can be slow), so only if hashes.csv absent
  if($hashRows.Count -eq 0){
    $found = Get-ChildItem -Path $RawDir -Recurse -File -Filter $fileName -ErrorAction SilentlyContinue | Select-Object -First 1
    return $null -ne $found
  }
  return $false
}

# Helper: check for redacted file presence; RedactedVersion may be a relative path or a filename
function Test-RedactedExists([string]$redactedField){
  if([string]::IsNullOrWhiteSpace($redactedField)){ return $false }
  $candidate = Join-Path $RedactedDir $redactedField
  if(Test-Path $candidate){ return $true }
  # If only a filename was provided, search recursively under redacted dir
  if(Test-Path $RedactedDir){
    $found = Get-ChildItem -Path $RedactedDir -Recurse -File -Filter (Split-Path -Leaf $redactedField) -ErrorAction SilentlyContinue | Select-Object -First 1
    return $null -ne $found
  }
  return $false
}

# Validate required columns exist in Evidence-Index.csv when file present
$requiredCols = @('ID','FileName','Description','Source','DateCollected','Relevance','HashSHA256','RedactedVersion','Notes')
$missingColumns = @()
if($indexRows.Count -gt 0){
  $cols = @()
  if($indexRows.Count -gt 0){ $cols = ($indexRows[0].PSObject.Properties | Select-Object -ExpandProperty Name) }
  foreach($c in $requiredCols){ if($cols -notcontains $c){ $missingColumns += $c } }
}

# Duplicate ID detection (ignore blank IDs)
$duplicateIds = @()
if($indexRows.Count -gt 0){
  $groups = $indexRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ID) } | Group-Object -Property ID
  $duplicateIds = @($groups | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name)
}

# Missing HashSHA256 in index
$indexMissingHash = @()
if($indexRows.Count -gt 0){
  $indexMissingHash = @($indexRows | Where-Object { [string]::IsNullOrWhiteSpace($_.HashSHA256) })
}

# Hash in index not found in hashes.csv
$indexHashNotInHashes = @()
if($indexRows.Count -gt 0 -and $hashRows.Count -gt 0){
  $indexHashNotInHashes = @($indexRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.HashSHA256) -and -not $shaToFile.ContainsKey($_.HashSHA256) })
}

# FileName in index not present on disk (based on hashes map or fallback scan)
$indexFileMissing = @()
if($indexRows.Count -gt 0){
  $indexFileMissing = @($indexRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.FileName) -and -not (Test-FileNameExists $_.FileName) })
}

# RedactedVersion missing on disk
$missingRedacted = @()
if($indexRows.Count -gt 0){
  $missingRedacted = @($indexRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.RedactedVersion) -and -not (Test-RedactedExists $_.RedactedVersion) })
}

# Orphan raw files: present in hashes.csv but not referenced by index (by SHA256 or FileName)
$orphanFiles = @()
if($hashRows.Count -gt 0){
  $indexHashes = ($indexRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.HashSHA256) } | Select-Object -ExpandProperty HashSHA256) | Sort-Object -Unique
  $indexFileNames = ($indexRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.FileName) } | Select-Object -ExpandProperty FileName) | Sort-Object -Unique
  foreach($h in $hashRows){
    $refByHash = ($indexHashes -contains $h.SHA256)
    $refByName = ($indexFileNames -contains $h.FileName)
    if(-not $refByHash -and -not $refByName){ $orphanFiles += $h }
  }
}

# Prepare report
Ensure-Directory $OutReport
$sb = New-Object System.Text.StringBuilder

function Add-Line([string]$s){ [void]$sb.AppendLine($s) }

Add-Line "# Evidence validation report"
Add-Line ""
Add-Line ("Generated: {0}" -f $now.ToString('yyyy-MM-dd HH:mm:ss'))
Add-Line ""
Add-Line "## Summary"
Add-Line ""
Add-Line ("- Index rows: {0}" -f $indexRows.Count)
Add-Line ("- Hash rows: {0}" -f $hashRows.Count)
Add-Line ("- Raw files (known): {0}" -f $rawFiles.Count)
Add-Line ("- Missing columns in index: {0}" -f ($missingColumns -join ', '))
Add-Line ("- Duplicate IDs: {0}" -f $($duplicateIds.Count))
Add-Line ("- Index rows missing HashSHA256: {0}" -f $($indexMissingHash.Count))
Add-Line ("- Index hashes not found in hashes.csv: {0}" -f $($indexHashNotInHashes.Count))
Add-Line ("- Index FileName not found on disk: {0}" -f $($indexFileMissing.Count))
Add-Line ("- Redacted files missing: {0}" -f $($missingRedacted.Count))
Add-Line ("- Orphan raw files (not referenced by index): {0}" -f $($orphanFiles.Count))
Add-Line ""

if($missingColumns.Count -gt 0){
  Add-Line "## Missing required columns in Evidence-Index.csv"
  Add-Line ""
  foreach($c in $missingColumns){ Add-Line ("- {0}" -f $c) }
  Add-Line ""
}

if($duplicateIds.Count -gt 0){
  Add-Line "## Duplicate IDs"
  Add-Line ""
  foreach($id in $duplicateIds){ Add-Line ("- {0}" -f $id) }
  Add-Line ""
}

if($indexMissingHash.Count -gt 0){
  Add-Line "## Index rows missing HashSHA256"
  Add-Line ""
  $indexMissingHash | Select-Object ID, FileName, Description | ForEach-Object { Add-Line ("- ID: {0} | File: {1} | {2}" -f $_.ID, $_.FileName, $_.Description) }
  Add-Line ""
}

if($indexHashNotInHashes.Count -gt 0){
  Add-Line "## Index hashes not present in hashes.csv"
  Add-Line ""
  $indexHashNotInHashes | Select-Object ID, FileName, HashSHA256 | ForEach-Object { Add-Line ("- ID: {0} | File: {1} | Hash: {2}" -f $_.ID, $_.FileName, $_.HashSHA256) }
  Add-Line ""
}

if($indexFileMissing.Count -gt 0){
  Add-Line "## Index FileName entries not found on disk"
  Add-Line ""
  $indexFileMissing | Select-Object ID, FileName | ForEach-Object { Add-Line ("- ID: {0} | File: {1}" -f $_.ID, $_.FileName) }
  Add-Line ""
}

if($missingRedacted.Count -gt 0){
  Add-Line "## RedactedVersion files missing"
  Add-Line ""
  $missingRedacted | Select-Object ID, RedactedVersion | ForEach-Object { Add-Line ("- ID: {0} | Redacted: {1}" -f $_.ID, $_.RedactedVersion) }
  Add-Line ""
}

if($orphanFiles.Count -gt 0){
  Add-Line "## Orphan raw files (not referenced by index)"
  Add-Line ""
  foreach($o in $orphanFiles){ Add-Line ("- {0} | {1} | {2}" -f $o.FileName, $o.SHA256, $o.FilePath) }
  Add-Line ""
}

[IO.File]::WriteAllText($OutReport, $sb.ToString())
Write-Output ("Wrote validation report → {0}" -f $OutReport)


