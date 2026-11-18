$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
$root = $env:JW_DOWNLOAD_HOME
if (-not $root) { $root = $PSScriptRoot }
$manifest = Get-Content -LiteralPath (Join-Path $root 'download-manifest.json') -Raw | ConvertFrom-Json
if ($manifest.archive -ne 'Journey_Within_Windows_Package.zip') { throw 'Unexpected archive name.' }
$target = Join-Path $root $manifest.archive
function ValidFile($path, $size, $sha) {
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
if ((Get-Item -LiteralPath $path).Length -ne [long]$size) { return $false }
return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $sha
}
if (ValidFile $target $manifest.bytes $manifest.sha256) { Write-Host 'The complete ZIP is already downloaded and verified.'; exit 0 }
$cache = Join-Path $root 'download-parts'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$i = 0
foreach ($part in $manifest.parts) {
$i++
if ($part.name -notmatch '^Journey_Within_Windows_Package\.zip\.part[0-9]{3}$') { throw 'Unsafe part filename.' }
$expectedUrl = 'https://github.com/KanishkThakar/journey-within-downloads/releases/download/v1.0.0/' + $part.name
if ($part.url -ne $expectedUrl) { throw 'Unexpected download address.' }
$path = Join-Path $cache $part.name
Write-Host ('Part ' + $i + ' of ' + $manifest.parts.Count + ': ' + $part.name)
if (ValidFile $path $part.bytes $part.sha256) { Write-Host 'Verified cached part; skipping download.'; continue }
$ok = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
$client = New-Object Net.WebClient
try {
Write-Host ('Downloading ' + [math]::Round($part.bytes / 1GB, 2) + ' GB. This may take several minutes.')
$client.DownloadFile($part.url, $path + '.partial')
if (-not (ValidFile ($path + '.partial') $part.bytes $part.sha256)) { throw 'Part checksum mismatch.' }
Move-Item -LiteralPath ($path + '.partial') -Destination $path -Force
$ok = $true
break
} catch {
Write-Host ('Attempt ' + $attempt + ' failed: ' + $_.Exception.Message)
if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
} finally { $client.Dispose() }
}
if (-not $ok) { throw 'Download stopped. Run the downloader again to resume from verified parts.' }
}
Write-Host 'Joining the parts into the complete ZIP...'
$temp = $target + '.assembling'
$output = [IO.File]::Open($temp, [IO.FileMode]::Create, [IO.FileAccess]::Write)
try {
foreach ($part in $manifest.parts) {
$inputFile = [IO.File]::OpenRead((Join-Path $cache $part.name))
try { $inputFile.CopyTo($output) } finally { $inputFile.Dispose() }
}
} finally { $output.Dispose() }
Write-Host 'Verifying the complete 29.3 GB ZIP. Please wait...'
if (-not (ValidFile $temp $manifest.bytes $manifest.sha256)) { throw 'Final ZIP checksum mismatch. The download parts have been kept.' }
if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination ($target + '.old-' + [DateTime]::Now.ToString('yyyyMMddHHmmss')) }
Move-Item -LiteralPath $temp -Destination $target
foreach ($part in $manifest.parts) { Remove-Item -LiteralPath (Join-Path $cache $part.name) }
Write-Host 'SUCCESS: complete ZIP verified. Temporary download parts removed.'
Write-Host 'Right-click Journey_Within_Windows_Package.zip, choose Extract All, then open index.html inside the extracted folder.'
} catch { Write-Host ('ERROR: ' + $_.Exception.Message); exit 1 }
