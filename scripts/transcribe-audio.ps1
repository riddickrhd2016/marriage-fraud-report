param(
  [string]$AudioRoot = './02-evidence/raw',
  [string]$OutDir = './04-logs/audio',
  [string]$Model = 'small',
  [string]$Language = 'en',
  [switch]$VerboseConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ if($VerboseConsole){ Write-Host $msg } }

function Resolve-Python(){
  $p = Get-Command python -ErrorAction SilentlyContinue
  if($p){ return $p.Source }
  $p = Get-Command py -ErrorAction SilentlyContinue
  if($p){ return $p.Source }
  throw 'Python not found in PATH. Install Python and retry.'
}

function Get-AudioFiles([string]$root){
  $exts = @('.m4a','.mp3','.wav','.aac','.flac','.ogg','.wma')
  return Get-ChildItem -Path $root -Recurse -File -ErrorAction Stop | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$python = Resolve-Python
$files = Get-AudioFiles -root $AudioRoot | Sort-Object FullName

$manifest = @()
$i = 0
foreach($f in $files){
  $i++
  if(($i % 5) -eq 0){ Write-Info ("Transcribing {0}/{1}: {2}" -f $i, $files.Count, $f.Name) }
  $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  $outBase = Join-Path $OutDir $base
  # Skip if transcript already exists
  $txt = $outBase + '.txt'
  if(-not (Test-Path $txt)){
    & $python -m whisper $f.FullName --model $Model --language $Language --task transcribe --output_format txt --output_dir $OutDir | Out-Null
  }
  $manifest += [pscustomobject]@{
    AudioPath = $f.FullName
    TranscriptTxt = $txt
    LastWriteTime = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
  }
}

$manifestPath = Join-Path $OutDir 'audio-manifest.csv'
$manifest | Export-Csv -NoTypeInformation -Path $manifestPath
Write-Output ("Transcribed {0} audio file(s). Manifest: {1}" -f $manifest.Count, $manifestPath)


