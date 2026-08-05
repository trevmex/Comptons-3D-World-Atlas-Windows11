[CmdletBinding()]
param(
    [string] $MirrorRoot = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe\Online Archive\Mirror')
)

$ErrorActionPreference = 'Stop'
$errors = New-Object Collections.Generic.List[string]
function Require([bool] $Condition, [string] $Message) {
    if (-not $Condition) { $script:errors.Add($Message) }
}

Require (Test-Path -LiteralPath $MirrorRoot) "Archive mirror is missing: $MirrorRoot"
if (Test-Path -LiteralPath $MirrorRoot) {
    $required = @(
        '3datlas\index.html',
        '3datlas\download\f_main_dl.html',
        '3datlas\sitemap.html',
        '3datlas\entry-links.html',
        'comptons\index.html',
        'manifests\mirror-manifest.json',
        'manifests\download-failures.json'
    )
    foreach ($relative in $required) {
        Require (Test-Path -LiteralPath (Join-Path $MirrorRoot $relative)) "Required archive target is missing: $relative"
    }

    $failurePath = Join-Path $MirrorRoot 'manifests\download-failures.json'
    if (Test-Path -LiteralPath $failurePath) {
        $failures = Get-Content -LiteralPath $failurePath -Raw | ConvertFrom-Json
        $failureCount = if ($null -eq $failures) { 0 } else { $failures.Count }
        Require ($failureCount -eq 0) "The archive contains $failureCount download failures."
    }

    $manifestPath = Join-Path $MirrorRoot 'manifests\mirror-manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Require (@($manifest.files).Count -ge 100) "The archive manifest contains unexpectedly few files: $(@($manifest.files).Count)."
        $missing = New-Object Collections.Generic.List[string]
        foreach ($entry in @($manifest.files)) {
            if (-not (Test-Path -LiteralPath (Join-Path $MirrorRoot $entry.local))) {
                $missing.Add($entry.local)
            }
        }
        Require ($missing.Count -eq 0) "The archive manifest lists $($missing.Count) missing files."
    }

    # The mirror is intended to be offline. Same-site links are rewritten by
    # the synchronizer; unresolved network URLs must not remain in clickable
    # HTML attributes or form actions.
    $networkReferences = New-Object Collections.Generic.List[string]
    foreach ($html in (Get-ChildItem -LiteralPath $MirrorRoot -Recurse -File |
        Where-Object { $_.Extension -match '(?i)^\.s?html?$' -or $_.Extension -ieq '.css' })) {
        $text = Get-Content -LiteralPath $html.FullName -Raw
        if ($text -match '(?i)(?:href|src|action|poster|background)\s*=\s*["''](?:https?:|//|mailto:)' -or
            $text -match '(?i)(?:url|@import)\s*\([^)]*(?:https?:|//)') {
            $networkReferences.Add($html.FullName)
        }
    }
    Require ($networkReferences.Count -eq 0) "Offline HTML still contains network attributes in $($networkReferences.Count) files."
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

$fileCount = @(Get-ChildItem -LiteralPath $MirrorRoot -Recurse -File).Count
[pscustomobject]@{
    Status = 'PASS'
    MirrorRoot = $MirrorRoot
    Files = $fileCount
    Manifest = (Join-Path $MirrorRoot 'manifests\mirror-manifest.json')
} | Format-List
