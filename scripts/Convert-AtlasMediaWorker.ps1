[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $InputPath,
    [Parameter(Mandatory = $true)] [string] $OutputPath,
    [Parameter(Mandatory = $true)] [string] $FfmpegPath,
    [Parameter(Mandatory = $true)] [string] $FfprobePath
)

$ErrorActionPreference = 'Stop'

function Invoke-Probe([string] $Path) {
    $raw = (& $FfprobePath -v error -show_streams -show_format -of json -- $Path 2>$null | Out-String).Trim()
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

$parsedItems = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
$items = @($parsedItems | ForEach-Object { $_ })
$results = New-Object Collections.Generic.List[object]
foreach ($item in $items) {
    $sourceInfo = Invoke-Probe $item.SourcePath
    $sourceVideo = Get-VideoStream $sourceInfo
    if (-not $sourceVideo) { throw "No video stream was found in $($item.OriginalSource)." }
    $sourceAudio = @(Get-AudioStreams $sourceInfo)
    $sourceCodec = "$($sourceVideo.codec_name)"
    $temporary = "$($item.Destination).partial-$PID.avi"
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue

    if ($sourceCodec -match '(?i)^indeo') {
        & $FfmpegPath -hide_banner -loglevel error -nostdin -y -i $item.SourcePath `
            -map 0:v:0 -map '0:a?' -c:v msvideo1 -pix_fmt rgb555le -vtag MSVC `
            -fps_mode passthrough -c:a copy -- $temporary
        if ($LASTEXITCODE) { throw "ffmpeg failed for $($item.FileName)." }
    } else {
        Copy-Item -LiteralPath $item.SourcePath -Destination $temporary -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $item.Destination) -Force | Out-Null
    Move-Item -LiteralPath $temporary -Destination $item.Destination -Force

    $replacementInfo = Invoke-Probe $item.Destination
    $replacementVideo = Get-VideoStream $replacementInfo
    $replacementCodec = "$($replacementVideo.codec_name)"
    if ($sourceCodec -match '(?i)^indeo' -and $replacementCodec -ne 'msvideo1') {
        throw "The converted codec for $($item.FileName) is '$replacementCodec', not Microsoft Video 1."
    }
    if ($replacementCodec -match '(?i)indeo') { throw "Obsolete Indeo remains in $($item.Destination)." }
    $replacementAudio = @(Compare-AudioStreams $sourceInfo $replacementInfo $item.FileName)

    $results.Add([pscustomobject]@{
        SourceRelative = $item.SourceRelative
        FileName = $item.FileName
        Source = $item.OriginalSource
        Replacement = $item.Destination
        SourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.SourcePath).Hash
        ReplacementSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.Destination).Hash
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

$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
