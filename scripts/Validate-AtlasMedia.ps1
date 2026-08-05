param(
    [string] $MediaRoot = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe\Converted Media')
)

$ErrorActionPreference = 'Stop'
$ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
$files = @(Get-ChildItem -LiteralPath $MediaRoot -Recurse -File | Where-Object {
    $_.Extension -match '(?i)^\.(avi|wav)$'
})
$failed = New-Object Collections.Generic.List[string]
$indeo = New-Object Collections.Generic.List[string]
foreach ($file in $files) {
    & $ffmpeg -nostdin -v error -xerror -i $file.FullName -map '0:v?' -map '0:a?' -f null NUL 2>$null
    if ($LASTEXITCODE) { $failed.Add($file.FullName) }
    if ($file.Extension -ieq '.avi') {
        $codec = (& $ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $file.FullName 2>$null | Out-String).Trim()
        if ($codec -match '(?i)^indeo[345]$') { $indeo.Add($file.FullName) }
    }
}
[pscustomobject]@{
    MediaRoot = $MediaRoot
    Files = $files.Count
    DecodeFailures = $failed.Count
    IndeoFiles = $indeo.Count
} | Format-List
if ($failed.Count -or $indeo.Count) {
    $failed | ForEach-Object { Write-Error "Decode failed: $_" }
    $indeo | ForEach-Object { Write-Error "Obsolete Indeo codec remains: $_" }
    exit 1
}
