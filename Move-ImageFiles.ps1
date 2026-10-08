<#
.SYNOPSIS
    Moves image files in a folder to a subfolder (e.g. "images" or "pics").

.DESCRIPTION
    Scans a source path AND all its subdirectories for common image file
    types and moves them into a subfolder underneath that path.
    Creates the subfolder if needed. Skips files already in the
    destination and auto-renames on collision.

.PARAMETER Path
    Source folder to scan. Defaults to current directory.

.PARAMETER DestinationName
    Name of the subfolder to create/move into. Defaults to "images".
    Can be a simple name ("pics") or relative path ("images/2026").

.PARAMETER NoRecurse
    Only scan the top-level folder. By default subfolders are searched too.
    Files in the destination folder itself are always excluded.

.PARAMETER Recurse
    Kept for backwards compatibility. Recursion is now the default, so this
    switch is accepted but has no effect. Use -NoRecurse to disable it.

.PARAMETER Include
    Override the list of file extensions to match. Include the dot, e.g. ".jpg".

.PARAMETER Force
    Overwrite existing files in the destination instead of renaming with a
    numeric suffix (e.g. photo_1.jpg).

.EXAMPLE
    .\Move-ImageFiles.ps1
    Moves images from current folder and all subfolders into .\images\

.EXAMPLE
    .\Move-ImageFiles.ps1 -Path "C:\Photos" -DestinationName "pics"
    Moves images from C:\Photos and subfolders into C:\Photos\pics\

.EXAMPLE
    .\Move-ImageFiles.ps1 -Path ./Downloads -NoRecurse
    Moves only top-level images (ignores subfolders).

.EXAMPLE
    .\Move-ImageFiles.ps1 -Path ./Downloads -Verbose
    Moves images recursively, with detailed output.

.EXAMPLE
    .\Move-ImageFiles.ps1 -Path ./Downloads -WhatIf
    Previews what would be moved without moving anything.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",

    [Parameter(Position = 1)]
    [string]$DestinationName = "images",

    [switch]$NoRecurse,

    [switch]$Recurse,

    [string[]]$Include = @(
        ".jpg", ".jpeg", ".png", ".gif", ".bmp",
        ".tiff", ".tif", ".webp", ".heic", ".heif",
        ".svg", ".ico", ".avif",
        ".raw", ".cr2", ".cr3", ".nef", ".arw", ".dng", ".orf", ".rw2",
        ".psd", ".ai", ".eps"
    ),

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 1. Resolve and validate source path
try {
    $sourceDir = (Resolve-Path -Path $Path -ErrorAction Stop).Path
} catch {
    Write-Error "Source path not found: $Path"
    return
}
if (-not (Test-Path -Path $sourceDir -PathType Container)) {
    Write-Error "Source path is not a folder: $sourceDir"
    return
}

# 2. Resolve destination folder (supports nested names like "pics/2026")
$destDir = Join-Path -Path $sourceDir -ChildPath $DestinationName

if (-not (Test-Path -Path $destDir -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($destDir, "Create destination folder")) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Write-Verbose "Created folder: $destDir"
    }
}
# Resolve for reliable comparison (handles WhatIf where folder may not exist yet)
$destDirFull = [System.IO.Path]::GetFullPath($destDir)

# 3. Normalize extensions to lowercase with leading dot
$extensions = $Include | ForEach-Object {
    $e = $_.Trim().ToLowerInvariant()
    if (-not $e.StartsWith(".")) { $e = ".$e" }
    $e
}

# 4. Collect candidate files (recursive by default, -NoRecurse for top-level only)
$getChildParams = @{
    Path = $sourceDir
    File = $true
}
if (-not $NoRecurse) { $getChildParams['Recurse'] = $true }

$files = Get-ChildItem @getChildParams | Where-Object {
    # Exclude anything already inside the destination
    $_.FullName -ne $destDirFull -and
    -not $_.FullName.StartsWith($destDirFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and
    ($extensions -contains $_.Extension.ToLowerInvariant())
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "No image files found in '$sourceDir'."
    return
}

# 5. Move files
$moved = 0
$skipped = 0
$renamed = 0

foreach ($file in $files) {
    $targetPath = Join-Path -Path $destDirFull -ChildPath $file.Name

    # Handle name collision by appending _1, _2, ... unless -Force
    if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $ext  = $file.Extension
        $i = 1
        do {
            $candidate = "{0}_{1}{2}" -f $base, $i, $ext
            $targetPath = Join-Path -Path $destDirFull -ChildPath $candidate
            $i++
        } while (Test-Path -LiteralPath $targetPath)
        $renamed++
        Write-Verbose "$($file.Name) -> $(Split-Path $targetPath -Leaf) (renamed to avoid collision)"
    }

    if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $targetPath")) {
        try {
            Move-Item -LiteralPath $file.FullName -Destination $targetPath -Force:$Force -ErrorAction Stop
            $moved++
            Write-Verbose "Moved: $($file.Name) -> $targetPath"
        } catch {
            $skipped++
            Write-Warning "Skipped '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}

Write-Host "Done. Moved: $moved | Renamed (collision): $renamed | Skipped/errors: $skipped | Destination: $destDirFull"
