#Requires -Version 5.1
<#
.SYNOPSIS
    Video Converter Script V2 - Powerful, flexible, and extensible.
.DESCRIPTION
    A complete rewrite of the video conversion script with advanced features:
    - Batch processing
    - JSON-based preset system
    - Parallel encoding ("Turbo Mode")
    - GIF/Thumbnail creation
    - Desktop notifications
#>

# --- Strict Mode and Console Encoding ---
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --- Global Configuration ---
$presetsFile = Join-Path $PSScriptRoot "presets.json"
# Using 'global' scope to make presets easily accessible everywhere.
$global:Presets = @{}

# =================================================================
# --- PRESET MANAGEMENT FUNCTIONS ---
# =================================================================

function Load-Presets {
    if (-not (Test-Path $presetsFile)) {
        Write-Error "Presets file '$presetsFile' not found. Please create it or place it next to the script."
        return $false
    }
    try {
        $jsonContent = Get-Content $presetsFile -Raw
        $global:Presets = $jsonContent | ConvertFrom-Json
        Write-Host "Presets loaded successfully." -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Error reading or parsing the presets file: $($_.Exception.Message)"
        return $false
    }
}

function Save-Presets {
    try {
        $jsonContent = $global:Presets | ConvertTo-Json -Depth 5
        Set-Content -Path $presetsFile -Value $jsonContent
        Write-Host "Presets saved successfully." -ForegroundColor Green
    } catch {
        Write-Error "Could not save presets: $($_.Exception.Message)"
    }
}

# =================================================================
# --- USER INTERFACE (UI) FUNCTIONS ---
# =================================================================

function Show-MainMenu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           FFMPEG VIDEO CONVERTER PRO V2           ║" -ForegroundColor White
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [1] Convert a single file"
    Write-Host " [2] Convert a folder (Turbo Mode available)"
    Write-Host " [3] Create GIF / Thumbnail"
    Write-Host " [4] Manage Presets"
    Write-Host ""
    Write-Host " [Q] Quit"
    Write-Host ""
    return Read-Host "Your choice"
}

function Manage-Presets {
    # Placeholder for management (create, delete, edit)
    Write-Host "--- Preset Management ---" -ForegroundColor Yellow
    Write-Host "Current presets:"
    foreach ($presetProperty in $global:Presets.PSObject.Properties) {
        Write-Host "- $($presetProperty.Name): $($presetProperty.Value.description)"
    }
    # Logic to add/delete/edit presets will be added here.
}

# =================================================================
# --- CONVERSION ENGINE ---
# =================================================================

function Show-PresetSelectionMenu {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Presets
    )

    Clear-Host
    Write-Host "--- Preset Selection ---" -ForegroundColor Yellow
    $presetNames = @($Presets.Keys) | Sort-Object
    for ($i = 0; $i -lt $presetNames.Count; $i++) {
        $name = $presetNames[$i]
        $desc = $Presets[$name].description
        Write-Host (" [{0}] {1,-20} - {2}" -f ($i + 1), $name, $desc)
    }
    Write-Host ""

    do {
        $input = Read-Host "Choose a preset (1-$($presetNames.Count))"
        try {
            $selection = [int]$input
            if ($selection -ge 1 -and $selection -le $presetNames.Count) {
                return $presetNames[$selection - 1]
            }
        } catch {}
        Write-Warning "Please enter a valid number."
    } while ($true)
}

function Get-VideoDuration {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    try {
        $ffprobeArgs = @('-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', $FilePath)
        $durationString = & ffprobe $ffprobeArgs 2>&1 | Out-String
        # ffprobe might return nothing or fail for weird files
        if ([string]::IsNullOrWhiteSpace($durationString)) { return 0 }
        return [double]::Parse($durationString.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        Write-Warning "Could not determine video duration for '$FilePath'. Progress percentage will not be available. Error: $($_.Exception.Message)"
        return 0
    }
}

function Invoke-FFmpegConversion {
    param(
        [Parameter(Mandatory=$true)] [string]$SourcePath,
        [Parameter(Mandatory=$true)] [string]$OutputPath,
        [Parameter(Mandatory=$true)] [psobject]$Preset
    )

    $ffmpegArgs = @(
        '-i', $SourcePath,
        '-c:v', $Preset.vcodec,
        '-preset', $Preset.preset,
        '-pix_fmt', $Preset.pix_fmt
    )
    if ($Preset.PSObject.Properties['crf']) { $ffmpegArgs += @('-crf', $Preset.crf) }
    if ($Preset.PSObject.Properties['cq']) { $ffmpegArgs += @('-cq', $Preset.cq) }

    if ($Preset.acodec -eq 'copy') {
        $ffmpegArgs += @('-c:a', 'copy')
    } else {
        $ffmpegArgs += @('-c:a', $Preset.acodec, '-b:a', $Preset.abitrate)
    }

    if ($Preset.extra_args) {
        $ffmpegArgs += $Preset.extra_args.Split(' ')
    }

    # Using -progress pipe:1 sends machine-readable output to stdout
    # Using -v quiet -stats sends the final summary to stderr
    $ffmpegArgs += @('-y', '-progress', 'pipe:1', '-v', 'quiet', '-stats', $OutputPath)

    Write-Host "Starting FFmpeg for '$([System.IO.Path]::GetFileName($SourcePath))'..." -ForegroundColor Cyan

    $duration = Get-VideoDuration -FilePath $SourcePath
    $lastErrorLine = ''
    $success = $false

    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo.FileName = 'ffmpeg'
        # Powershell's argument list quoting is tricky. This is a reliable way.
        $process.StartInfo.Arguments = $ffmpegArgs -join ' '
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.CreateNoWindow = $true

        $progressData = @{}
        $outputHandler = {
            param($line)
            if ($line -eq $null) { return }

            $parts = $line.Split('=')
            if ($parts.Length -eq 2) {
                $progressData[$parts[0].Trim()] = $parts[1].Trim()
            }

            if ($progressData.ContainsKey('out_time_ms') -and $duration -gt 0) {
                $elapsedUs = [decimal]$progressData['out_time_ms']
                $percentage = [int](($elapsedUs / ($duration * 1000000)) * 100)
                $percentage = if ($percentage -gt 100) { 100 } else { $percentage }

                $status = "Progress: $percentage% | Speed: $($progressData.speed)"
                Write-Progress -Activity "Converting '$([System.IO.Path]::GetFileName($SourcePath))'" -Status $status -PercentComplete $percentage
            }
        }

        $errorHandler = { param($line) if ($line) { $global:lastErrorLine = $line } }

        $process.Start() | Out-Null

        # Asynchronously read stdout and stderr
        $process.OutputDataReceived.Subscribe($outputHandler)
        $process.ErrorDataReceived.Subscribe($errorHandler)
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()

        $process.WaitForExit()

        # Finalize progress bar
        Write-Progress -Activity "Converting '$([System.IO.Path]::GetFileName($SourcePath))'" -Completed

        if ($process.ExitCode -eq 0) {
            Write-Host "Conversion of '$SourcePath' completed successfully!" -ForegroundColor Green
            $success = $true
        } else {
            Write-Error "FFmpeg encountered an error on '$SourcePath'. Exit code: $($process.ExitCode). Last error: $global:lastErrorLine"
        }
    } catch {
        Write-Error "An exception occurred while running FFmpeg: $($_.Exception.Message)"
    } finally {
        # Clean up the event subscriptions
        $process.OutputDataReceived.RemoveAll()
        $process.ErrorDataReceived.RemoveAll()
    }
    return $success
}

function Start-SingleFileConversion {
    Write-Host "--- Single File Conversion ---" -ForegroundColor Yellow

    # 1. Select source file
    $sourcePath = Read-Host "Please drag and drop the video file here, or paste the full path"
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        Write-Error "File not found or not a file: '$sourcePath'"
        return
    }

    # 2. Select preset
    $selectedPresetName = Show-PresetSelectionMenu -Presets $global:Presets
    $preset = $global:Presets.($selectedPresetName)

    # 3. Manage output file
    $sourceDir = [System.IO.Path]::GetDirectoryName($sourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $outputDir = Join-Path $sourceDir "converted"
    if (-not (Test-Path $outputDir)) {
        Write-Host "Creating output directory: $outputDir"
        New-Item -Path $outputDir -ItemType Directory | Out-Null
    }
    $suggestedFileName = "${sourceBaseName}_${selectedPresetName}.${preset.container}"
    $outputPath = Join-Path $outputDir $suggestedFileName
    
    # Overwrite check
    if (Test-Path $outputPath) {
        $overwrite = Read-Host "The output file '$outputPath' already exists. Overwrite? [y/N]"
        if ($overwrite.ToLower() -ne 'y') {
            Write-Host "Conversion cancelled." -ForegroundColor Red
            return
        }
    }
    Write-Host "File will be saved at: $outputPath" -ForegroundColor Cyan

    # 4. Call the conversion engine
    if (Invoke-FFmpegConversion -SourcePath $sourcePath -OutputPath $outputPath -Preset $preset) {
        Show-ToastNotification -Title "Conversion Complete" -Message "'$([System.IO.Path]::GetFileName($outputPath))' was created successfully."
    }
}

function Start-BatchConversion {
    Write-Host "--- Batch Conversion (Folder) ---" -ForegroundColor Yellow

    # 1. Select source folder
    $sourceFolder = Read-Host "Please drag and drop the folder to process here, or paste the full path"
    if (-not (Test-Path $sourceFolder -PathType Container)) {
        Write-Error "Folder not found or path is invalid: '$sourceFolder'"
        return
    }

    # 2. Find video files
    $videoExtensions = @("*.mp4", "*.mkv", "*.mov", "*.m4v", "*.avi", "*.ts", "*.m2ts", "*.webm")
    $filesToConvert = Get-ChildItem -Path $sourceFolder -Include $videoExtensions -Recurse

    if (-not $filesToConvert) {
        Write-Warning "No video files found in the specified folder."
        return
    }

    Write-Host "$($filesToConvert.Count) video files found."

    # 3. Select preset for the batch
    $selectedPresetName = Show-PresetSelectionMenu -Presets $global:Presets
    $preset = $global:Presets.($selectedPresetName)

    # 4. Conversion loop
    $outputDir = Join-Path $sourceFolder "converted"
    if (-not (Test-Path $outputDir)) {
        Write-Host "Creating output directory: $outputDir"
        New-Item -Path $outputDir -ItemType Directory | Out-Null
    }

    $successCount = 0
    $failCount = 0

    $useTurbo = Read-Host "Enable Turbo Mode (parallel encoding)? [Y/n]"
    if ($useTurbo.ToLower() -ne 'n') {
        # --- Turbo Mode (Parallel) ---
        $maxConcurrentJobs = [System.Environment]::ProcessorCount
        Write-Host "Turbo Mode enabled. Starting up to $maxConcurrentJobs parallel conversions." -ForegroundColor Green

        # Setup temp directory for progress files
        $progressDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -Path $progressDir -ItemType Directory | Out-Null

        $runningJobs = @{} # Use a hashtable to store job and its metadata
        $filesQueue = [System.Collections.Generic.Queue[System.IO.FileInfo]]::new($filesToConvert)
        $totalFiles = $filesToConvert.Count
        $processedCount = 0

        try {
            while ($processedCount -lt $totalFiles) {
                # Start new jobs if there are free slots
                while ($runningJobs.Count -lt $maxConcurrentJobs -and $filesQueue.Count -gt 0) {
                    $file = $filesQueue.Dequeue()
                    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
                    $suggestedFileName = "${sourceBaseName}_${selectedPresetName}.${preset.container}"
                    $outputPath = Join-Path $outputDir $suggestedFileName

                    if ($file.DirectoryName -eq $outputDir) {
                        Write-Warning "File '$($file.Name)' is already in the output directory. Skipping."
                        $processedCount++
                        continue
                    }

                    $progressFilePath = Join-Path $progressDir "progress-$($file.Name).txt"
                    $duration = Get-VideoDuration -FilePath $file.FullName

                    $scriptBlock = {
                        param($sourcePath, $outPath, $currentPreset, $progPath)
                        $ffmpegArgs = @('-i', $sourcePath, '-c:v', $currentPreset.vcodec, '-preset', $currentPreset.preset, '-pix_fmt', $currentPreset.pix_fmt)
                        if ($currentPreset.PSObject.Properties['crf']) { $ffmpegArgs += @('-crf', $currentPreset.crf) }
                        if ($currentPreset.PSObject.Properties['cq']) { $ffmpegArgs += @('-cq', $currentPreset.cq) }
                        if ($currentPreset.acodec -eq 'copy') { $ffmpegArgs += @('-c:a', 'copy') } else { $ffmpegArgs += @('-c:a', $currentPreset.acodec, '-b:a', $currentPreset.abitrate) }
                        if ($currentPreset.extra_args) { $ffmpegArgs += $currentPreset.extra_args.Split(' ') }
                        # Use -progress to write to a file, makes it easy to monitor
                        $ffmpegArgs += @('-y', '-progress', $progPath, '-v', 'error', $outPath)
                        & ffmpeg $ffmpegArgs
                        return @{ Success = ($LASTEXITCODE -eq 0); FileName = $sourcePath }
                    }

                    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $file.FullName, $outputPath, $preset, $progressFilePath
                    $job.Name = $file.Name
                    $runningJobs[$job.Id] = @{ Job = $job; ProgressFile = $progressFilePath; Duration = $duration; FileName = $file.Name }
                    Write-Host "Starting conversion for $($job.Name)..."
                }

                # Update overall progress
                Write-Progress -Id 0 -Activity "Batch Conversion (Turbo Mode)" -Status "Completed $processedCount of $totalFiles files." -PercentComplete ($processedCount * 100 / $totalFiles)

                # Update progress for running jobs
                foreach ($jobInfo in $runningJobs.Values) {
                    $jobId = $jobInfo.Job.Id
                    $progressContent = Get-Content $jobInfo.ProgressFile -ErrorAction SilentlyContinue | Select-Object -Last 1
                    if ($progressContent) {
                        $progressData = @{}
                        $progressContent.Split([environment]::NewLine) | ForEach-Object {
                            $parts = $_.Split('=')
                            if ($parts.Length -eq 2) { $progressData[$parts[0].Trim()] = $parts[1].Trim() }
                        }

                        if ($progressData.ContainsKey('out_time_ms') -and $jobInfo.Duration -gt 0) {
                            $elapsedUs = [decimal]$progressData['out_time_ms']
                            $percentage = [int](($elapsedUs / ($jobInfo.Duration * 1000000)) * 100)
                            $percentage = if ($percentage -gt 100) { 100 } else { $percentage }
                            Write-Progress -Id $jobId -ParentId 0 -Activity "Converting $($jobInfo.FileName)" -Status "Speed: $($progressData.speed)" -PercentComplete $percentage
                        }
                    }
                }

                # Check for finished jobs without blocking
                $finishedJob = Get-Job | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') -and $runningJobs.ContainsKey($_.Id) }
                if ($finishedJob) {
                    foreach ($job in $finishedJob) {
                        $jobResult = Receive-Job -Job $job
                        $processedCount++
                        Write-Host "($processedCount/$totalFiles) Task finished for '$($job.Name)'." -ForegroundColor Gray
                        if ($jobResult.Success) { $successCount++ } else { $failCount++; Write-Warning "Conversion of $($jobResult.FileName) failed." }

                        Write-Progress -Id $job.Id -Completed # Remove progress bar for finished job
                        Remove-Job -Job $job
                        $runningJobs.Remove($job.Id)
                    }
                }
                Start-Sleep -Milliseconds 500
            }
        } finally {
            # Cleanup
            Write-Progress -Id 0 -Completed
            Remove-Item -Path $progressDir -Recurse -Force -ErrorAction SilentlyContinue
            Get-Job | Remove-Job -Force
        }
    } else {
        # --- Sequential Mode ---
        for ($i = 0; $i -lt $filesToConvert.Count; $i++) {
            $file = $filesToConvert[$i]
            Write-Host "------------------------------------------------------------"
            Write-Host "Converting file $($i+1)/$($filesToConvert.Count): $($file.Name)" -ForegroundColor White

            $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
            $suggestedFileName = "${sourceBaseName}_${selectedPresetName}.${preset.container}"
            $outputPath = Join-Path $outputDir $suggestedFileName

            if ($file.DirectoryName -eq $outputDir) {
                Write-Warning "File '$($file.Name)' is already in the output directory. Skipping."
                continue
            }

            if (Invoke-FFmpegConversion -SourcePath $file.FullName -OutputPath $outputPath -Preset $preset) {
                $successCount++
            } else {
                $failCount++
            }
        }
    }

    # --- Summary ---
    Write-Host "------------------------------------------------------------"
    Write-Host "Batch process finished." -ForegroundColor Green
    Write-Host "Succeeded: $successCount"
    Write-Host "Failed: $failCount" -ForegroundColor Red

    Show-ToastNotification -Title "Batch Process Finished" -Message "Succeeded: $successCount, Failed: $failCount."
}

# =================================================================
# --- NOTIFICATIONS & FINALIZATION ---
# =================================================================

function Install-ToastModuleIfMissing {
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Write-Host "Module 'BurntToast' for notifications is missing. Installing..." -ForegroundColor Yellow
        try {
            # Force confirmation to avoid prompts in non-interactive environments
            Install-Module -Name BurntToast -Scope CurrentUser -Force -Confirm:$false
            Write-Host "Module 'BurntToast' installed." -ForegroundColor Green
        } catch {
            Write-Warning "Could not install 'BurntToast'. Desktop notifications will be disabled."
        }
    }
}

function Show-ToastNotification {
    param(
        [string]$Title,
        [string]$Message
    )
    # Check if the module is available before trying to use it
    if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
        New-BurntToastNotification -Text $Title, $Message
    }
}

# =================================================================
# --- ADDITIONAL TOOLS ---
# =================================================================

function Create-AnimatedGif {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath
    )

    Write-Host ""
    Write-Host "--- Animated GIF Creation ---"

    # --- Parameter Collection ---
    $startTime = Read-Host "Enter start time (e.g., 00:01:23)"
    if ($startTime -notmatch '^\d{2}:\d{2}:\d{2}(\.\d+)?$') { Write-Error "Invalid time format."; return }

    $duration = Read-Host "Enter duration in seconds (e.g., 3.5)"
    if (-not ([double]::TryParse($duration, [ref]$null))) { Write-Error "Invalid duration. Use a number."; return }

    $fps = Read-Host "Enter frames per second (e.g., 15) [Default: 15]"
    if (-not $fps) { $fps = 15 }

    $width = Read-Host "Enter width in pixels (e.g., 480) [Default: 480]"
    if (-not $width) { $width = 480 }

    # --- Path Definition ---
    $sourceDir = [System.IO.Path]::GetDirectoryName($SourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $outputPath = Join-Path $sourceDir "${sourceBaseName}_${startTime.Replace(':', '-')}_${duration}s.gif"
    $palettePath = Join-Path ([System.IO.Path]::GetTempPath()) "palette.png"

    try {
        # --- Step 1: Palette Generation ---
        Write-Host "Step 1/2: Analyzing and generating color palette..." -ForegroundColor Cyan
        $vfPalette = "fps=$fps,scale=${width}:-1:flags=lanczos,palettegen"
        $ffmpegPaletteArgs = @('-y', '-ss', $startTime, '-t', $duration, '-i', $SourcePath, '-vf', $vfPalette, $palettePath)

        & ffmpeg $ffmpegPaletteArgs

        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg failed during palette generation."
        }

        # --- Step 2: GIF Creation with Palette ---
        Write-Host "Step 2/2: Creating GIF using palette..." -ForegroundColor Cyan
        $filterComplex = "fps=$fps,scale=${width}:-1:flags=lanczos[x];[x][1:v]paletteuse"
        $ffmpegGifArgs = @('-ss', $startTime, '-t', $duration, '-i', $SourcePath, '-i', $palettePath, '-filter_complex', $filterComplex, $outputPath)

        & ffmpeg -y $ffmpegGifArgs

        if ($LASTEXITCODE -eq 0) {
            Write-Host "GIF created successfully!" -ForegroundColor Green
            Write-Host $outputPath
        } else {
            throw "FFmpeg failed during GIF creation."
        }
    } catch {
        Write-Error $_.Exception.Message
    } finally {
        # --- Cleanup ---
        if (Test-Path $palettePath) {
            Remove-Item $palettePath -ErrorAction SilentlyContinue
        }
    }
}

function Create-Thumbnail {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath
    )

    Write-Host ""
    Write-Host "--- Thumbnail Creation ---"
    $timestamp = Read-Host "Enter timestamp for capture (e.g., 00:01:23) [Default: 00:00:10]"
    if (-not $timestamp) { $timestamp = '00:00:10' }

    # Simple regex validation for HH:MM:SS or HH:MM:SS.ms format
    if ($timestamp -notmatch '^\d{2}:\d{2}:\d{2}(\.\d+)?$') {
        Write-Error "Invalid time format. Use HH:MM:SS."
        return
    }

    $sourceDir = [System.IO.Path]::GetDirectoryName($SourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $outputPath = Join-Path $sourceDir "${sourceBaseName}_thumbnail.jpg"

    Write-Host "Creating thumbnail at '$outputPath'..." -ForegroundColor Cyan

    $ffmpegArgs = @(
        '-ss', $timestamp,
        '-i', $SourcePath,
        '-vframes', '1',
        '-q:v', '2', # JPEG quality (2-5 is a good range)
        $outputPath
    )

    # The -y option overwrites the output file without asking
    & ffmpeg -y $ffmpegArgs | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Thumbnail created successfully!" -ForegroundColor Green
        Write-Host $outputPath
    } else {
        Write-Error "FFmpeg failed during thumbnail creation. Check if the timestamp is valid."
    }
}

function Start-GifOrThumbnailCreation {
    Clear-Host
    Write-Host "--- GIF / Thumbnail Creator ---" -ForegroundColor Yellow

    # 1. Select source file
    $sourcePath = Read-Host "Please drag and drop the video file here, or paste the full path"
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        Write-Error "File not found or not a file: '$sourcePath'"
        return
    }

    # 2. Sub-menu for action choice
    Write-Host ""
    Write-Host "What do you want to create from '$([System.IO.Path]::GetFileName($sourcePath))'?"
    Write-Host "[1] An animated GIF"
    Write-Host "[2] A still thumbnail"
    $choice = Read-Host "Your choice"

    switch($choice) {
        '1' { Create-AnimatedGif -SourcePath $sourcePath }
        '2' { Create-Thumbnail -SourcePath $sourcePath }
        default { Write-Warning "Invalid choice." }
    }
}


# =================================================================
# --- MAIN SCRIPT ---
# =================================================================

function Main {
    # Dependency check on startup
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Error "FFmpeg was not found. Please install it and add it to your system's PATH."
        Read-Host "Press Enter to exit."; return
    }

    if (-not (Load-Presets)) {
        Read-Host "Press Enter to exit."; return
    }

    # Attempt to install notification module on first run
    Install-ToastModuleIfMissing

    Start-Sleep -Seconds 1

    # Main program loop
    while ($true) {
        $choice = Show-MainMenu

        switch ($choice) {
            '1' { Start-SingleFileConversion }
            '2' { Start-BatchConversion }
            '3' { Start-GifOrThumbnailCreation }
            '4' { Manage-Presets }
            'Q' { Write-Host "Goodbye!"; return }
            default { Write-Warning "Invalid choice." }
        }

        Write-Host ""
        Read-Host "Press Enter to return to the main menu..."
    }
}

# --- Script Launch ---
Main
