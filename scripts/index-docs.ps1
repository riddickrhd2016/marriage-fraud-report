param(
  [string[]]$Roots = @('./02-evidence/raw/E-009-DrugPaymentEmails','./02-evidence/raw/E-010-BackgroundCheckDocs','./02-evidence/raw/E-011-EmploymentAliasesDocs'),
  [string]$OutIndexCsv = './04-logs/docs-index.csv',
  [string]$OutChronoCsv = './04-logs/docs-chronology.csv',
  [string[]]$IncludeKeywords = @('USCIS','immigration','ID','license','alias','aka','payment','drug','receipt','Cash App','Zelle','Venmo','Western Union'),
  [string[]]$ExcludeKeywords = @('[Your Name]','SSN','account','bank','medical'),
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

function Resolve-PdfToText(){
  $cmd = Get-Command pdftotext -ErrorAction SilentlyContinue
  if($cmd){ return $cmd.Source }
  $cand = Get-ChildItem -Path 'C:\Program Files','C:\Program Files (x86)','C:\' -Filter pdftotext.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if($cand){ return $cand.FullName }
  return $null
}

function Get-Bucket([string]$path){
  try {
    $rawRoot = (Resolve-Path -Path './02-evidence/raw').Path
    $full = (Resolve-Path -Path $path).Path
    if($full.StartsWith($rawRoot,[System.StringComparison]::OrdinalIgnoreCase)){
      $rel = $full.Substring($rawRoot.Length) -replace '^[\\/]+',''
      return ($rel -split '[\\/]')[0]
    }
  } catch { }
  return ''
}

$pdfToText = Resolve-PdfToText
if(-not $pdfToText){ Write-Info 'pdftotext not found; PDFs will be indexed by filename only.' }

$includeRegexes = $IncludeKeywords | ForEach-Object { [regex]::new([regex]::Escape($_), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
$excludeRegexes = $ExcludeKeywords | ForEach-Object { [regex]::new([regex]::Escape($_), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }

$allFiles = @()
foreach($root in $Roots){
  if(Test-Path $root){
    $allFiles += Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue
  }
}

$indexRows = @()
$chronoRows = @()
foreach($f in ($allFiles | Sort-Object FullName)){
  $bucket = Get-Bucket $f.FullName
  $ext = $f.Extension.ToLowerInvariant()
  $text = ''
  if($ext -eq '.pdf' -and $pdfToText){
    $tmpTxt = Join-Path $env:TEMP (New-Guid).Guid + '.txt'
    & $pdfToText -layout -enc UTF-8 $f.FullName $tmpTxt 2>$null
    if(Test-Path $tmpTxt){ $text = Get-Content -Path $tmpTxt -Raw -ErrorAction SilentlyContinue; Remove-Item $tmpTxt -ErrorAction SilentlyContinue }
  } elseif($ext -in @('.txt','.md','.csv','.log')){
    $text = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
  } elseif($ext -eq '.eml'){
    # Basic header scrape
    $lines = Get-Content -Path $f.FullName -TotalCount 50 -ErrorAction SilentlyContinue
    $text = ($lines -join "`n")
  }

  $incHits = 0; foreach($rx in $includeRegexes){ if($rx.IsMatch($text)){ $incHits++ } }
  $excHits = 0; foreach($rx in $excludeRegexes){ if($rx.IsMatch($text)){ $excHits++ } }
  $concern = $excHits -gt 0

  $indexRows += [pscustomobject]@{
    EvidenceBucket = $bucket
    FilePath = $f.FullName
    FileName = $f.Name
    Extension = $ext
    SizeBytes = $f.Length
    LastWriteTime = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    IncludeHits = $incHits
    ExcludeHits = $excHits
    ConcernFlag = $concern
    TextPreview = if([string]::IsNullOrWhiteSpace($text)) { '' } else { $text.Substring(0, [Math]::Min(400, $text.Length)).Replace("`r`n"," ").Replace("`n"," ") }
  }

  $chronoRows += [pscustomobject]@{
    When = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    Source = 'Document'
    EvidenceBucket = $bucket
    FilePath = $f.FullName
    SHA256 = ''
    Title = $f.Name
    Body = ''
    EvidenceRefs = ''
    IncludeHits = $incHits
    ExcludeHits = $excHits
    ConcernFlag = $concern
  }
}

$indexRows | Export-Csv -NoTypeInformation -Path $OutIndexCsv
$chronoRows | Sort-Object When, Title | Export-Csv -NoTypeInformation -Path $OutChronoCsv

Write-Output ("Indexed {0} document(s). Index: {1} | Chronology: {2}" -f $indexRows.Count, $OutIndexCsv, $OutChronoCsv)


