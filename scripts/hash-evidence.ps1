param([string]$RawPath = './02-evidence/raw',[string]$OutCsv = './04-logs/hashes.csv')
$items = Get-ChildItem -Path $RawPath -File -Recurse
$rows = @()
foreach($it in $items){
  $h = Get-FileHash -Algorithm SHA256 -Path $it.FullName
  $rows += [pscustomobject]@{ ID = ''; FilePath = $it.FullName; FileName = $it.Name; SizeBytes = $it.Length; SHA256 = $h.Hash }
}
$rows | Export-Csv -NoTypeInformation -Path $OutCsv
Write-Output "Wrote $($rows.Count) hashes to $OutCsv"
