[CmdletBinding()]
param(
    [string] $DiscDrive = 'D:',
    [string] $OutputRoot = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe\Converted Media'),
    [string] $FfmpegPath = '',
    [string] $FfprobePath = '',
    [switch] $PreserveExistingOutput
)

$ErrorActionPreference = 'Stop'
$drive = $DiscDrive.TrimEnd('\')

function Resolve-Tool([string] $Requested, [string] $Name) {
    if ($Requested) {
        if (-not (Test-Path -LiteralPath $Requested)) { throw "$Name was not found at $Requested." }
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    return (Get-Command $Name -ErrorAction Stop).Source
}

$ffmpeg = Resolve-Tool $FfmpegPath 'ffmpeg.exe'
$ffprobe = Resolve-Tool $FfprobePath 'ffprobe.exe'
$aviRoot = Join-Path $OutputRoot 'AVI'
$gameRoot = Join-Path $OutputRoot 'GAME'
$gameMovieRoot = Join-Path $gameRoot 'MOVIES'
$discAvi = Join-Path $drive 'AVI'
$discGame = Join-Path $drive 'GAME'
$discGameMovies = Join-Path $discGame 'MOVIES'
$miniflag = Join-Path $discGame 'MINIFLAG.AVI'

$sourceFiles = New-Object Collections.Generic.List[System.IO.FileInfo]
if (Test-Path -LiteralPath $discAvi) {
    foreach ($file in (Get-ChildItem -LiteralPath $discAvi -File -Filter '*.avi')) { $sourceFiles.Add($file) }
}
if (Test-Path -LiteralPath $discGameMovies) {
    foreach ($file in (Get-ChildItem -LiteralPath $discGameMovies -File -Filter '*.avi')) { $sourceFiles.Add($file) }
}
if (Test-Path -LiteralPath $miniflag) {
    $sourceFiles.Add((Get-Item -LiteralPath $miniflag))
}
if (-not $sourceFiles.Count) { throw "No Atlas AVI files were found on $drive." }

function Invoke-Probe([string] $Path) {
    $raw = (& $ffprobe -v error -show_streams -show_format -of json -- $Path 2>$null | Out-String).Trim()
    if ($LASTEXITCODE) { throw "ffprobe could not read $Path." }
    try { return ($raw | ConvertFrom-Json) }
    catch { throw "ffprobe returned invalid metadata for ${Path}: $($_.Exception.Message)" }
}

function Get-Streams($Info) {
    if ($null -eq $Info.streams) { return @() }
    return @($Info.streams)
}

function Get-VideoStream($Info) {
    return @(Get-Streams $Info | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1)[0]
}

function Get-AudioStreams($Info) {
    return @(Get-Streams $Info | Where-Object { $_.codec_type -eq 'audio' })
}

function Compare-AudioStreams($Source, $Replacement, [string] $Name) {
    $sourceAudio = @(Get-AudioStreams $Source)
    $replacementAudio = @(Get-AudioStreams $Replacement)
    if ($sourceAudio.Count -ne $replacementAudio.Count) {
        throw "Audio stream count changed for $Name ($($sourceAudio.Count) to $($replacementAudio.Count))."
    }
    for ($index = 0; $index -lt $sourceAudio.Count; $index++) {
        $left = $sourceAudio[$index]
        $right = $replacementAudio[$index]
        foreach ($property in @('codec_name', 'channels', 'sample_rate')) {
            if ("$($left.$property)" -ne "$($right.$property)") {
                throw "Audio $property changed for $Name."
            }
        }
    }
    return $sourceAudio
}

$ffmpegVersion = ((& $ffmpeg -hide_banner -version 2>$null | Select-Object -First 1).ToString()).Trim()

if (-not $PreserveExistingOutput -and (Test-Path -LiteralPath $OutputRoot)) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $aviRoot, $gameMovieRoot -Force | Out-Null

$manifest = New-Object Collections.Generic.List[object]
$convertedCount = 0
$seenDestinations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $sourceFiles) {
    $isGameMovie = $file.FullName.StartsWith(($discGameMovies.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
    $isMiniFlag = $file.FullName -ieq $miniflag
    if ($isGameMovie) {
        $destinationDirectory = $gameMovieRoot
        $sourceRelative = 'GAME\MOVIES\' + $file.Name
    } elseif ($isMiniFlag) {
        $destinationDirectory = $gameRoot
        $sourceRelative = 'GAME\' + $file.Name
    } else {
        $destinationDirectory = $aviRoot
        $sourceRelative = 'AVI\' + $file.Name
    }
    $destination = Join-Path $destinationDirectory $file.Name.ToUpperInvariant()
    if (-not $seenDestinations.Add($destination)) { throw "Duplicate media destination: $destination" }

    $sourceInfo = Invoke-Probe $file.FullName
    $sourceVideo = Get-VideoStream $sourceInfo
    if (-not $sourceVideo) { throw "No video stream was found in $($file.FullName)." }
    $sourceAudio = @(Get-AudioStreams $sourceInfo)
    $sourceCodec = "$($sourceVideo.codec_name)"
    $temporary = "$destination.partial.avi"
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue

    if ($sourceCodec -match '(?i)^indeo') {
        & $ffmpeg -hide_banner -loglevel error -nostdin -y -i $file.FullName `
            -map 0:v:0 -map '0:a?' -c:v msvideo1 -pix_fmt rgb555le -vtag MSVC `
            -fps_mode passthrough -c:a copy -- $temporary
        if ($LASTEXITCODE) { throw "ffmpeg failed for $($file.Name)." }
        $convertedCount++
    } else {
        Copy-Item -LiteralPath $file.FullName -Destination $temporary -Force
    }
    Move-Item -LiteralPath $temporary -Destination $destination -Force

    $replacementInfo = Invoke-Probe $destination
    $replacementVideo = Get-VideoStream $replacementInfo
    $replacementCodec = "$($replacementVideo.codec_name)"
    if ($sourceCodec -match '(?i)^indeo' -and $replacementCodec -ne 'msvideo1') {
        throw "The converted codec for $($file.Name) is '$replacementCodec', not Microsoft Video 1."
    }
    if ($replacementCodec -match '(?i)^indeo') { throw "Obsolete Indeo remains in $destination." }
    $replacementAudio = @(Compare-AudioStreams $sourceInfo $replacementInfo $file.Name)

    $manifest.Add([pscustomobject]@{
        SourceRelative = $sourceRelative
        FileName = $file.Name.ToUpperInvariant()
        Source = $file.FullName
        Replacement = $destination
        SourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        ReplacementSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        SourceCodec = $sourceCodec
        ReplacementCodec = $replacementCodec
        AudioStreams = $sourceAudio.Count
        AudioCodecs = (($replacementAudio | ForEach-Object { $_.codec_name }) -join ',')
        VideoWidth = $replacementVideo.width
        VideoHeight = $replacementVideo.height
        DurationSeconds = $replacementVideo.duration
        Converted = ($sourceCodec -match '(?i)^indeo')
    })
}

if (Test-Path -LiteralPath $discGame) {
    Get-ChildItem -LiteralPath $discGame -File | Where-Object {
        $_.Name -ine 'MINIFLAG.AVI' -and $_.Extension -notmatch '(?i)^\.avi$'
    } | Copy-Item -Destination $gameRoot -Force
    $gameSounds = Join-Path $discGame 'SOUNDS'
    if (Test-Path -LiteralPath $gameSounds) {
        $destinationSounds = Join-Path $gameRoot 'SOUNDS'
        New-Item -ItemType Directory -Path $destinationSounds -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $gameSounds '*') -Destination $destinationSounds -Force
    }
}

$manifestPath = Join-Path $aviRoot 'conversion-manifest.tsv'
$manifest | Export-Csv -LiteralPath $manifestPath -Delimiter "`t" -NoTypeInformation -Encoding UTF8
$inventory = [ordered]@{
    GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
    Disc = $drive
    OutputRoot = $OutputRoot
    Ffmpeg = $ffmpeg
    FfmpegVersion = $ffmpegVersion
    Files = $manifest.Count
    Converted = $convertedCount
    GameMovies = @($manifest | Where-Object { $_.SourceRelative -like 'GAME\MOVIES\*' }).Count
    Manifest = $manifestPath
}
$inventory | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot 'media-inventory.json') -Encoding UTF8
[pscustomobject]$inventory | Format-List
