param(
    [string] $DiscDrive = 'D:',
    [string] $OutputRoot = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe\Converted Media')
)

$ErrorActionPreference = 'Stop'
$drive = $DiscDrive.TrimEnd('\')
$ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
$aviRoot = Join-Path $OutputRoot 'AVI'
$gameRoot = Join-Path $OutputRoot 'GAME'
$gameMovieRoot = Join-Path $gameRoot 'MOVIES'
New-Item -ItemType Directory -Path $aviRoot, $gameMovieRoot -Force | Out-Null

function Invoke-Probe([string[]] $arguments) {
    (& $ffprobe @arguments 2>$null | Out-String).Trim()
}

$files = @()
$discAvi = Join-Path $drive 'AVI'
$discGameMovies = Join-Path $drive 'GAME\MOVIES'
if (Test-Path -LiteralPath $discAvi) {
    $files += Get-ChildItem -LiteralPath $discAvi -File -Filter '*.avi'
}
if (Test-Path -LiteralPath $discGameMovies) {
    $files += Get-ChildItem -LiteralPath $discGameMovies -File -Filter '*.avi'
}
if (-not $files.Count) { throw "No Atlas AVI files were found on $drive." }

$manifest = New-Object Collections.Generic.List[object]
$gameMoviePath = if (Test-Path -LiteralPath $discGameMovies) { (Resolve-Path -LiteralPath $discGameMovies).Path } else { '' }
foreach ($file in $files) {
    $isGame = [bool]$gameMoviePath -and $file.Directory.FullName -ieq $gameMoviePath
    $destinationDirectory = if ($isGame) { $gameMovieRoot } else { $aviRoot }
    $destination = Join-Path $destinationDirectory $file.Name.ToUpperInvariant()
    $sourceCodec = Invoke-Probe @('-v','error','-select_streams','v:0','-show_entries','stream=codec_name','-of','default=noprint_wrappers=1:nokey=1',$file.FullName)
    $audioStreams = @(Invoke-Probe @('-v','error','-select_streams','a','-show_entries','stream=index','-of','csv=p=0',$file.FullName) -split '\r?\n' | Where-Object { $_ })

    if ($sourceCodec -match '(?i)^indeo[345]$') {
        $temporary = "$destination.partial.avi"
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        & $ffmpeg -hide_banner -loglevel error -nostdin -y -i $file.FullName `
            -map 0:v:0 -map '0:a?' -c:v msvideo1 -pix_fmt rgb555le -vtag MSVC `
            -fps_mode passthrough -c:a copy $temporary
        if ($LASTEXITCODE) { throw "ffmpeg failed for $($file.Name)." }
        Move-Item -LiteralPath $temporary -Destination $destination -Force
        $replacementCodec = Invoke-Probe @('-v','error','-select_streams','v:0','-show_entries','stream=codec_name','-of','default=noprint_wrappers=1:nokey=1',$destination)
        if ($replacementCodec -ne 'msvideo1') { throw "The converted codec for $($file.Name) is not Microsoft Video 1." }
    } else {
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        $replacementCodec = $sourceCodec
    }

    $manifest.Add([pscustomobject]@{
        FileName = $file.Name.ToUpperInvariant()
        Source = $file.FullName
        Replacement = $destination
        SourceCodec = $sourceCodec
        ReplacementCodec = $replacementCodec
        AudioStreams = $audioStreams.Count
    })
}

$gameSource = Join-Path $drive 'GAME'
$miniflag = Join-Path $gameSource 'MINIFLAG.AVI'
if (Test-Path -LiteralPath $miniflag) {
    $destination = Join-Path $gameRoot 'MINIFLAG.AVI'
    $sourceCodec = Invoke-Probe @('-v','error','-select_streams','v:0','-show_entries','stream=codec_name','-of','default=noprint_wrappers=1:nokey=1',$miniflag)
    if ($sourceCodec -match '(?i)^indeo[345]$') {
        $temporary = "$destination.partial.avi"
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        & $ffmpeg -hide_banner -loglevel error -nostdin -y -i $miniflag `
            -map 0:v:0 -map '0:a?' -c:v msvideo1 -pix_fmt rgb555le -vtag MSVC `
            -fps_mode passthrough -c:a copy $temporary
        if ($LASTEXITCODE) { throw 'ffmpeg failed for MINIFLAG.AVI.' }
        Move-Item -LiteralPath $temporary -Destination $destination -Force
        $replacementCodec = 'msvideo1'
    } else {
        Copy-Item -LiteralPath $miniflag -Destination $destination -Force
        $replacementCodec = $sourceCodec
    }
    $manifest.Add([pscustomobject]@{
        FileName = 'MINIFLAG.AVI'; Source = $miniflag; Replacement = $destination
        SourceCodec = $sourceCodec; ReplacementCodec = $replacementCodec; AudioStreams = 0
    })
}
if (Test-Path -LiteralPath $gameSource) {
    Get-ChildItem -LiteralPath $gameSource -File | Where-Object { $_.Extension -notmatch '(?i)^\.avi$' } |
        Copy-Item -Destination $gameRoot -Force
    $gameSounds = Join-Path $gameSource 'SOUNDS'
    if (Test-Path -LiteralPath $gameSounds) {
        New-Item -ItemType Directory -Path (Join-Path $gameRoot 'SOUNDS') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $gameSounds '*') -Destination (Join-Path $gameRoot 'SOUNDS') -Force
    }
}

$manifestPath = Join-Path $aviRoot 'conversion-manifest.tsv'
$manifest | Export-Csv -LiteralPath $manifestPath -Delimiter "`t" -NoTypeInformation -Encoding UTF8
[pscustomobject]@{
    Disc = $drive
    Files = $manifest.Count
    Converted = @($manifest | Where-Object SourceCodec -match '(?i)^indeo[345]$').Count
    OutputRoot = $OutputRoot
    Manifest = $manifestPath
} | Format-List
