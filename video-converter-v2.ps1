#Requires -Version 5.1
<#
.SYNOPSIS
    A streamlined, menu-driven PowerShell wrapper for the Advanced Video Converter suite.
.DESCRIPTION
    This script provides a user-friendly command-line interface for the core Python conversion engine.
    - Manages conversion presets using presets.json.
    - Converts single files or entire folders sequentially.
    - Creates animated GIFs and thumbnails.
    - All FFmpeg logic is delegated to the central `core/ffmpeg_core.py` script for consistency.
#>

# --- Strict Mode and Environment ---
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --- Global Configuration ---
$ScriptRoot = $PSScriptRoot
$PresetsFile = Join-Path $ScriptRoot "presets.json"
$PythonCoreScript = Join-Path $ScriptRoot "core" "ffmpeg_core.py"
$global:Presets = @{}

# =================================================================
# --- CORE FUNCTIONS ---
# =================================================================

function Load-Presets {
    if (-not (Test-Path $PresetsFile)) {
        Write-Error "Presets file '$PresetsFile' not found."
        return $false
    }
    try {
        $jsonContent = Get-Content $PresetsFile -Raw
        $global:Presets = $jsonContent | ConvertFrom-Json
        Write-Host "Presets loaded successfully." -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Error reading or parsing presets.json: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-PythonCore {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments
    )

    Write-Host "Executing: python3 $($Arguments -join ' ')" -ForegroundColor DarkGray

    try {
        # Start the process and stream output. This provides real-time feedback.
        # Using Start-Process with -PassThru and Wait-Process is robust.
        $process = Start-Process "python3" -ArgumentList $Arguments -PassThru -NoNewWindow -RedirectStandardOutput "$PSScriptRoot/stdout.log" -RedirectStandardError "$PSScriptRoot/stderr.log"
        Wait-Process -Id $process.Id

        # Now, handle the output from the log files
        $stdout = Get-Content "$PSScriptRoot/stdout.log" -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content "$PSScriptRoot/stderr.log" -Raw -ErrorAction SilentlyContinue

        if ($process.ExitCode -ne 0) {
            Write-Error "Python script failed with exit code $($process.ExitCode)."
            if ($stderr) {
                Write-Error "Error output: $stderr"
            }
            return $false
        }

        # The Python script now outputs JSON. Let's parse it for a better experience.
        foreach ($line in $stdout.Split("`n")) {
            if ($line) {
                $data = $line | ConvertFrom-Json
                if ($data.type -eq 'progress') {
                    $percentage = $data.percentage
                    $message = $data.message
                    if ($percentage -ge 0) {
                        Write-Progress -Activity "Conversion in progress" -Status $message -PercentComplete $percentage
                    }
                } elseif ($data.type -eq 'success') {
                    Write-Host $data.message -ForegroundColor Green
                } elseif ($data.type -eq 'error') {
                    Write-Error $data.message
                }
            }
        }
        Write-Progress -Activity "Conversion in progress" -Completed
        return $true

    } catch {
        Write-Error "Failed to execute Python script: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item "$PSScriptRoot/stdout.log" -ErrorAction SilentlyContinue
        Remove-Item "$PSScriptRoot/stderr.log" -ErrorAction SilentlyContinue
    }
}


# =================================================================
# --- UI AND WORKFLOW FUNCTIONS ---
# =================================================================

function Show-MainMenu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        ADVANCED VIDEO CONVERTER (PowerShell)      ║" -ForegroundColor White
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [1] Convert a single file"
    Write-Host " [2] Convert all files in a folder"
    Write-Host " [3] Create GIF / Thumbnail"
    Write-Host " [4] View Presets"
    Write-Host ""
    Write-Host " [Q] Quit"
    Write-Host ""
    return Read-Host "Your choice"
}

function Show-PresetSelectionMenu {
    Clear-Host
    Write-Host "--- Preset Selection ---" -ForegroundColor Yellow
    $presetNames = @($global:Presets.PSObject.Properties.Name) | Sort-Object
    for ($i = 0; $i -lt $presetNames.Count; $i++) {
        $name = $presetNames[$i]
        $desc = $global:Presets.$name.description
        Write-Host (" [{0}] {1,-20} - {2}" -f ($i + 1), $name, $desc)
    }
    Write-Host ""
    do {
        $input = Read-Host "Choose a preset (1-$($presetNames.Count))"
        try {
            if ([int]$input -ge 1 -and [int]$input -le $presetNames.Count) {
                return $presetNames[[int]$input - 1]
            }
        } catch {}
        Write-Warning "Please enter a valid number."
    } while ($true)
}

function Start-SingleFileConversion {
    Write-Host "--- Single File Conversion ---" -ForegroundColor Yellow
    $sourcePath = Read-Host "Drag & drop the video file here, or paste the full path"
    if (-not (Test-Path $sourcePath -PathType Leaf)) { Write-Error "File not found: '$sourcePath'"; return }

    $selectedPresetName = Show-PresetSelectionMenu
    $preset = $global:Presets.$selectedPresetName

    $sourceDir = [System.IO.Path]::GetDirectoryName($sourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $outputDir = Join-Path $sourceDir "converted"
    New-Item -Path $outputDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    $outputPath = Join-Path $outputDir "${sourceBaseName}_${selectedPresetName}.${preset.container}"
    
    if (Test-Path $outputPath) {
        if ((Read-Host "Output file exists. Overwrite? [y/N]").ToLower() -ne 'y') {
            Write-Host "Conversion cancelled."; return
        }
    }

    $qualityMode = if ($preset.crf) { 'crf' } elseif ($preset.cq) { 'cq' } else { 'cbr' }
    $qualityValue = if ($preset.crf) { $preset.crf } elseif ($preset.cq) { $preset.cq } else { $preset.cbr }

    $coreArgs = @(
        $PythonCoreScript, 'convert',
        $sourcePath, $outputPath,
        '--vcodec', $preset.vcodec,
        '--acodec', $preset.acodec,
        '--mode', $qualityMode,
        '--value', $qualityValue,
        '--hwaccel', 'none' # HW accel logic can be added here if needed from presets
    )

    if (Invoke-PythonCore -Arguments $coreArgs) {
        Show-ToastNotification -Title "Conversion Complete" -Message "'$([System.IO.Path]::GetFileName($outputPath))' created."
    }
}

function Start-BatchConversion {
    Write-Host "--- Batch Conversion ---" -ForegroundColor Yellow
    $sourceFolder = Read-Host "Drag & drop the folder to process here, or paste the full path"
    if (-not (Test-Path $sourceFolder -PathType Container)) { Write-Error "Folder not found: '$sourceFolder'"; return }

    $videoExtensions = @("*.mp4", "*.mkv", "*.mov", "*.m4v", "*.avi", "*.ts", "*.m2ts", "*.webm")
    $filesToConvert = Get-ChildItem -Path $sourceFolder -Include $videoExtensions -Recurse
    if (-not $filesToConvert) { Write-Warning "No video files found."; return }

    Write-Host "$($filesToConvert.Count) video files found."
    $selectedPresetName = Show-PresetSelectionMenu
    $preset = $global:Presets.$selectedPresetName
    $outputDir = Join-Path $sourceFolder "converted"
    New-Item -Path $outputDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

    $successCount = 0
    $failCount = 0

    foreach ($file in $filesToConvert) {
        if ($file.DirectoryName -eq $outputDir) { continue } # Skip files already in output dir

        Write-Host "------------------------------------------------------------"
        Write-Host "Processing $($file.Name)..." -ForegroundColor White
        $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
        $outputPath = Join-Path $outputDir "${sourceBaseName}_${selectedPresetName}.${preset.container}"

        $qualityMode = if ($preset.crf) { 'crf' } elseif ($preset.cq) { 'cq' } else { 'cbr' }
        $qualityValue = if ($preset.crf) { $preset.crf } elseif ($preset.cq) { $preset.cq } else { $preset.cbr }

        $coreArgs = @(
            $PythonCoreScript, 'convert',
            $file.FullName, $outputPath,
            '--vcodec', $preset.vcodec,
            '--acodec', $preset.acodec,
            '--mode', $qualityMode,
            '--value', $qualityValue
        )

        if (Invoke-PythonCore -Arguments $coreArgs) { $successCount++ } else { $failCount++ }
    }

    Write-Host "------------------------------------------------------------"
    Write-Host "Batch process finished. Succeeded: $successCount, Failed: $failCount" -ForegroundColor Green
    Show-ToastNotification -Title "Batch Process Finished" -Message "Succeeded: $successCount, Failed: $failCount."
}

function Start-GifOrThumbnailCreation {
    Clear-Host
    Write-Host "--- GIF / Thumbnail Creator ---" -ForegroundColor Yellow
    $sourcePath = Read-Host "Drag & drop the video file here, or paste the full path"
    if (-not (Test-Path $sourcePath -PathType Leaf)) { Write-Error "File not found: '$sourcePath'"; return }

    Write-Host "[1] Create Animated GIF"
    Write-Host "[2] Create Thumbnail"
    $choice = Read-Host "Your choice"

    $sourceDir = [System.IO.Path]::GetDirectoryName($sourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)

    if ($choice -eq '1') {
        $startTime = Read-Host "Enter start time (e.g., 00:01:23)"
        $duration = Read-Host "Enter duration in seconds (e.g., 3.5)"
        $outputPath = Join-Path $sourceDir "${sourceBaseName}_anim.gif"
        $coreArgs = @(
            $PythonCoreScript, 'gif',
            $sourcePath, $outputPath,
            '--start', $startTime,
            '--duration', $duration
        )
        Invoke-PythonCore -Arguments $coreArgs
    } elseif ($choice -eq '2') {
        $timestamp = Read-Host "Enter timestamp (e.g., 00:01:23)"
        $outputPath = Join-Path $sourceDir "${sourceBaseName}_thumb.jpg"
        $coreArgs = @(
            $PythonCoreScript, 'thumbnail',
            $sourcePath, $outputPath,
            '--timestamp', $timestamp
        )
        Invoke-PythonCore -Arguments $coreArgs
    } else {
        Write-Warning "Invalid choice."
    }
}

# =================================================================
# --- NOTIFICATIONS & MAIN SCRIPT ---
# =================================================================

function Install-ToastModuleIfMissing {
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Write-Host "Module 'BurntToast' for notifications is missing. Attempting to install..." -ForegroundColor Yellow
        try {
            Install-Module -Name BurntToast -Scope CurrentUser -Force -Confirm:$false
            Write-Host "Module 'BurntToast' installed." -ForegroundColor Green
        } catch {
            Write-Warning "Could not install 'BurntToast'. Desktop notifications will be disabled."
        }
    }
}

function Show-ToastNotification {
    param([string]$Title, [string]$Message)
    if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
        New-BurntToastNotification -Text $Title, $Message
    }
}

function Main {
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        Write-Error "python3 was not found. Please install Python and add it to your system's PATH."
        Read-Host "Press Enter to exit."; return
    }
    if (-not (Test-Path $PythonCoreScript)) {
        Write-Error "Core script not found at '$PythonCoreScript'."
        Read-Host "Press Enter to exit."; return
    }
    if (-not (Load-Presets)) {
        Read-Host "Press Enter to exit."; return
    }

    Install-ToastModuleIfMissing

    while ($true) {
        $choice = Show-MainMenu
        switch ($choice) {
            '1' { Start-SingleFileConversion }
            '2' { Start-BatchConversion }
            '3' { Start-GifOrThumbnailCreation }
            '4' { $global:Presets | ConvertTo-Json }
            'Q' { Write-Host "Goodbye!"; return }
            default { Write-Warning "Invalid choice." }
        }
        Write-Host ""
        Read-Host "Press Enter to return to the main menu..."
    }
}

# --- Script Launch ---
Main
