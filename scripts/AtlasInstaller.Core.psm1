Set-StrictMode -Version Latest

function Set-AtlasSectionBody {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Section,
        [Parameter(Mandatory)][string] $Body
    )

    $pattern = "(?ms)^\[$([regex]::Escape($Section))\]\r?\n(?<body>.*?)(?=^\[|\z)"
    $match = [regex]::Match($Text, $pattern)
    $replacement = "[$Section]`r`n$Body`r`n"
    if ($match.Success) {
        return $Text.Substring(0, $match.Index) + $replacement +
            $Text.Substring($match.Index + $match.Length)
    }
    return $Text.TrimEnd() + "`r`n`r`n$replacement"
}

function Set-AtlasSectionValue {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Section,
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][string] $Value
    )

    $pattern = "(?ms)^\[$([regex]::Escape($Section))\]\r?\n(?<body>.*?)(?=^\[|\z)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return $Text.TrimEnd() + "`r`n`r`n[$Section]`r`n$Key=$Value`r`n"
    }
    $body = $match.Groups['body'].Value
    $keyPattern = "(?im)^$([regex]::Escape($Key))\s*=.*$"
    if ([regex]::IsMatch($body, $keyPattern)) {
        $body = [regex]::Replace($body, $keyPattern, "$Key=$Value")
    } else {
        $body = $body.TrimEnd("`r", "`n") + "`r`n$Key=$Value`r`n"
    }
    return $Text.Substring(0, $match.Index) + "[$Section]`r`n$body" +
        $Text.Substring($match.Index + $match.Length)
}

function Get-AtlasFinalPath {
    param(
        [Parameter(Mandatory)][string] $StagedRoot,
        [Parameter(Mandatory)][string] $FinalRoot,
        [Parameter(Mandatory)][string] $StagedPath
    )

    $stagedFull = [IO.Path]::GetFullPath($StagedPath).TrimEnd('\')
    $stagedBase = [IO.Path]::GetFullPath($StagedRoot).TrimEnd('\')
    if (-not $stagedFull.StartsWith($stagedBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "The staged path is outside its staging root: $StagedPath"
    }
    $relative = $stagedFull.Substring($stagedBase.Length).TrimStart('\')
    return Join-Path $FinalRoot $relative
}

function Test-AtlasShimArtifact {
    param(
        [Parameter(Mandatory)][string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "The archive shim is missing: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x40) { throw 'The archive shim is too small to be a PE DLL.' }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($peOffset -lt 0 -or ($peOffset + 6) -gt $bytes.Length) {
        throw 'The archive shim has an invalid PE header.'
    }
    if ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550) {
        throw 'The archive shim does not contain a PE signature.'
    }
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    if ($machine -ne 0x014c) { throw 'The archive shim is not an x86 PE DLL.' }

    [pscustomobject]@{
        Path = (Resolve-Path -LiteralPath $Path).Path
        Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
        Machine = $machine
        IsX86 = $true
    }
}

function Publish-AtlasStagedDirectory {
    param(
        [Parameter(Mandatory)][string] $StagedPath,
        [Parameter(Mandatory)][string] $LivePath,
        [Parameter(Mandatory)][string] $TransactionId
    )

    if (-not (Test-Path -LiteralPath $StagedPath -PathType Container)) {
        throw "The staged installation directory is missing: $StagedPath"
    }
    $liveParent = Split-Path -Parent $LivePath
    if ($liveParent) { New-Item -ItemType Directory -Path $liveParent -Force | Out-Null }

    $backupPath = ''
    if (Test-Path -LiteralPath $LivePath) {
        $backupPath = "$LivePath.install-backup-$TransactionId"
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $LivePath -Destination $backupPath -Force -ErrorAction Stop | Out-Null
    }

    try {
        Move-Item -LiteralPath $StagedPath -Destination $LivePath -Force -ErrorAction Stop | Out-Null
    } catch {
        if (Test-Path -LiteralPath $LivePath) {
            Remove-Item -LiteralPath $LivePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $LivePath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        throw
    }
    return $backupPath
}

function Restore-AtlasPublishedDirectory {
    param(
        [Parameter(Mandatory)][string] $LivePath,
        [string] $BackupPath = '',
        [Parameter(Mandatory)][bool] $WasPublished
    )

    if (-not $WasPublished) { return }
    if (Test-Path -LiteralPath $LivePath) {
        Remove-Item -LiteralPath $LivePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
        Move-Item -LiteralPath $BackupPath -Destination $LivePath -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

Export-ModuleMember -Function @(
    'Get-AtlasFinalPath',
    'Publish-AtlasStagedDirectory',
    'Restore-AtlasPublishedDirectory',
    'Set-AtlasSectionBody',
    'Set-AtlasSectionValue',
    'Test-AtlasShimArtifact'
)
