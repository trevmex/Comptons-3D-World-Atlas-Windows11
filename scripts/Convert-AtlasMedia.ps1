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
$sourceStageRoot = Join-Path $OutputRoot '.source-stage'
$workerRoot = Join-Path $OutputRoot '.conversion-workers'

function Quote-ProcessArgument([string] $Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

try {
    New-Item -ItemType Directory -Path $sourceStageRoot, $workerRoot -Force | Out-Null
    $workItems = New-Object Collections.Generic.List[object]
    $stageIndex = 0
    Write-Host "Staging $($sourceFiles.Count) source movies for parallel conversion..."
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

        $stagedSource = Join-Path $sourceStageRoot ('{0:D3}-{1}' -f $stageIndex, $file.Name)
        Copy-Item -LiteralPath $file.FullName -Destination $stagedSource -Force
        $workItems.Add([pscustomobject]@{
            SourcePath = $stagedSource
            OriginalSource = $file.FullName
            SourceRelative = $sourceRelative
            FileName = $file.Name.ToUpperInvariant()
            Destination = $destination
        })
        $stageIndex++
    }

    $workerScript = Join-Path $PSScriptRoot 'Convert-AtlasMediaWorker.ps1'
    if (-not (Test-Path -LiteralPath $workerScript)) { throw "The media worker is missing: $workerScript" }
    $workerCount = [Math]::Max(1, [Math]::Min(4, [Environment]::ProcessorCount))
    $workerCount = [Math]::Min($workerCount, $workItems.Count)
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $workers = New-Object Collections.Generic.List[object]
    Write-Host "Converting and validating media with $workerCount parallel workers..."

    for ($workerIndex = 0; $workerIndex -lt $workerCount; $workerIndex++) {
        $batch = New-Object Collections.Generic.List[object]
        for ($itemIndex = $workerIndex; $itemIndex -lt $workItems.Count; $itemIndex += $workerCount) {
            $batch.Add($workItems[$itemIndex])
        }
        $inputPath = Join-Path $workerRoot ("input-{0}.json" -f $workerIndex)
        $outputPath = Join-Path $workerRoot ("output-{0}.json" -f $workerIndex)
        $stdoutPath = Join-Path $workerRoot ("stdout-{0}.log" -f $workerIndex)
        $stderrPath = Join-Path $workerRoot ("stderr-{0}.log" -f $workerIndex)
        $batch | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $inputPath -Encoding UTF8
        $parameters = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' + (Quote-ProcessArgument $workerScript) +
            ' -InputPath ' + (Quote-ProcessArgument $inputPath) +
            ' -OutputPath ' + (Quote-ProcessArgument $outputPath) +
            ' -FfmpegPath ' + (Quote-ProcessArgument $ffmpeg) +
            ' -FfprobePath ' + (Quote-ProcessArgument $ffprobe)
        $process = Start-Process -FilePath $powershell -ArgumentList $parameters -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $workers.Add([pscustomobject]@{
            Process = $process
            OutputPath = $outputPath
            StderrPath = $stderrPath
            WorkerIndex = $workerIndex
        })
    }

    foreach ($worker in $workers) {
        $worker.Process.WaitForExit()
        if ($worker.Process.ExitCode -or -not (Test-Path -LiteralPath $worker.OutputPath)) {
            $errorText = if (Test-Path -LiteralPath $worker.StderrPath) {
                (Get-Content -LiteralPath $worker.StderrPath -Raw).Trim()
            } else { '' }
            throw "Media worker $($worker.WorkerIndex) failed with exit code $($worker.Process.ExitCode) or produced no result. $errorText"
        }
        $parsedResults = Get-Content -LiteralPath $worker.OutputPath -Raw | ConvertFrom-Json
        foreach ($result in @($parsedResults | ForEach-Object { $_ })) {
            $manifest.Add($result)
        }
    }
    $convertedCount = @($manifest | Where-Object { $_.Converted }).Count
} finally {
    Remove-Item -LiteralPath $sourceStageRoot, $workerRoot -Recurse -Force -ErrorAction SilentlyContinue
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
