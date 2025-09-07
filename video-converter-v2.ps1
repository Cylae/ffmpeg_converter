#Requires -Version 5.1
<#
.SYNOPSIS
    Script de conversion vidéo V2 - Puissant, flexible et extensible.
.DESCRIPTION
    Une réécriture complète du script de conversion vidéo avec des fonctionnalités avancées :
    - Traitement par lots
    - Système de préréglages basé sur JSON
    - Encodage parallèle ("Turbo Mode")
    - Création de GIFs/Miniatures
    - Notifications de bureau
#>

# --- Configuration Stricte et Encodage de la Console ---
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --- Configuration Globale ---
$presetsFile = Join-Path $PSScriptRoot "presets.json"
# On utilise le scope 'global' pour que les préréglages soient facilement accessibles partout.
$global:Presets = @{}

# =================================================================
# --- FONCTIONS DE GESTION DES PRÉRÉGLAGES ---
# =================================================================

function Load-Presets {
    if (-not (Test-Path $presetsFile)) {
        Write-Error "Fichier de préréglages '$presetsFile' introuvable. Créez-le ou placez-le à côté du script."
        return $false
    }
    try {
        $jsonContent = Get-Content $presetsFile -Raw
        $global:Presets = $jsonContent | ConvertFrom-Json
        Write-Host "Préréglages chargés avec succès." -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Erreur lors de la lecture ou de l'analyse du fichier de préréglages : $($_.Exception.Message)"
        return $false
    }
}

function Save-Presets {
    try {
        $jsonContent = $global:Presets | ConvertTo-Json -Depth 5
        Set-Content -Path $presetsFile -Value $jsonContent
        Write-Host "Préréglages sauvegardés avec succès." -ForegroundColor Green
    } catch {
        Write-Error "Impossible de sauvegarder les préréglages : $($_.Exception.Message)"
    }
}

# =================================================================
# --- FONCTIONS D'INTERFACE UTILISATEUR (UI) ---
# =================================================================

function Show-MainMenu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           FFMPEG VIDEO CONVERTER PRO V2           ║" -ForegroundColor White
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [1] Convertir un fichier unique"
    Write-Host " [2] Convertir un dossier (Mode Turbo)"
    Write-Host " [3] Créer un GIF ou une miniature"
    Write-Host " [4] Gérer les préréglages"
    Write-Host ""
    Write-Host " [Q] Quitter"
    Write-Host ""
    return Read-Host "Votre choix"
}

function Manage-Presets {
    # Placeholder pour la gestion (créer, supprimer, éditer)
    Write-Host "--- Gestion des Préréglages ---" -ForegroundColor Yellow
    Write-Host "Préréglages actuels :"
    $global:Presets.PSObject.Properties | ForEach-Object {
        Write-Host "- $($_.Name): $($_.Value.description)"
    }
    # Ici, on ajoutera la logique pour ajouter/supprimer/modifier des préréglages.
}

# =================================================================
# --- MOTEUR DE CONVERSION ---
# =================================================================

function Show-PresetSelectionMenu {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Presets
    )

    Clear-Host
    Write-Host "--- Choix du Préréglage ---" -ForegroundColor Yellow
    $presetNames = @($Presets.Keys) | Sort-Object
    for ($i = 0; $i -lt $presetNames.Count; $i++) {
        $name = $presetNames[$i]
        $desc = $Presets[$name].description
        Write-Host (" [{0}] {1,-20} - {2}" -f ($i + 1), $name, $desc)
    }
    Write-Host ""

    do {
        $input = Read-Host "Choisissez un préréglage (1-$($presetNames.Count))"
        try {
            $selection = [int]$input
            if ($selection -ge 1 -and $selection -le $presetNames.Count) {
                return $presetNames[$selection - 1]
            }
        } catch {}
        Write-Warning "Veuillez entrer un nombre valide."
    } while ($true)
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

    $ffmpegArgs += $OutputPath

    Write-Host "Lancement de FFmpeg pour '$SourcePath'..." -ForegroundColor Cyan

    # Appel simple avec -y pour écraser. La barre de progression viendra plus tard.
    & ffmpeg -y $ffmpegArgs | Out-Null

    if($LASTEXITCODE -eq 0) {
        Write-Host "Conversion de '$SourcePath' terminée avec succès !" -ForegroundColor Green
        return $true
    } else {
        Write-Error "FFmpeg a rencontré une erreur sur '$SourcePath'. Code de sortie : $LASTEXITCODE"
        return $false
    }
}

function Start-SingleFileConversion {
    Write-Host "--- Conversion de Fichier Unique ---" -ForegroundColor Yellow

    # 1. Sélection du fichier source
    $sourcePath = Read-Host "Veuillez glisser-déposer le fichier vidéo ici, ou coller le chemin complet"
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        Write-Error "Fichier introuvable ou ce n'est pas un fichier : '$sourcePath'"
        return
    }

    # 2. Sélection du préréglage
    $selectedPresetName = Show-PresetSelectionMenu -Presets $global:Presets
    $preset = $global:Presets.($selectedPresetName)

    # 3. Gestion du fichier de sortie
    $sourceDir = [System.IO.Path]::GetDirectoryName($sourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $outputDir = Join-Path $sourceDir "converted"
    if (-not (Test-Path $outputDir)) {
        Write-Host "Création du dossier de sortie : $outputDir"
        New-Item -Path $outputDir -ItemType Directory | Out-Null
    }
    $suggestedFileName = "${sourceBaseName}_${selectedPresetName}.${preset.container}"
    $outputPath = Join-Path $outputDir $suggestedFileName

    # Vérification de l'écrasement
    if (Test-Path $outputPath) {
        $overwrite = Read-Host "Le fichier de sortie '$outputPath' existe déjà. L'écraser? [o/N]"
        if ($overwrite.ToLower() -ne 'o') {
            Write-Host "Conversion annulée." -ForegroundColor Red
            return
        }
    }
    Write-Host "Le fichier sera sauvegardé ici : $outputPath" -ForegroundColor Cyan

    # 4. Appel du moteur de conversion
    if (Invoke-FFmpegConversion -SourcePath $sourcePath -OutputPath $outputPath -Preset $preset) {
        Show-ToastNotification -Title "Conversion Terminée" -Message "'$([System.IO.Path]::GetFileName($outputPath))' a été créé avec succès."
    }
}

function Start-BatchConversion {
    Write-Host "--- Conversion par Lots (Dossier) ---" -ForegroundColor Yellow

    # 1. Sélection du dossier source
    $sourceFolder = Read-Host "Veuillez glisser-déposer le dossier à traiter ici, ou coller le chemin complet"
    if (-not (Test-Path $sourceFolder -PathType Container)) {
        Write-Error "Dossier introuvable ou chemin invalide : '$sourceFolder'"
        return
    }

    # 2. Trouver les fichiers vidéo
    $videoExtensions = @("*.mp4", "*.mkv", "*.mov", "*.m4v", "*.avi", "*.ts", "*.m2ts", "*.webm")
    $filesToConvert = Get-ChildItem -Path $sourceFolder -Include $videoExtensions -Recurse

    if (-not $filesToConvert) {
        Write-Warning "Aucun fichier vidéo trouvé dans le dossier spécifié."
        return
    }

    Write-Host "$($filesToConvert.Count) fichiers vidéo trouvés."

    # 3. Sélection du préréglage pour le lot
    $selectedPresetName = Show-PresetSelectionMenu -Presets $global:Presets
    $preset = $global:Presets.($selectedPresetName)

    # 4. Boucle de conversion
    $outputDir = Join-Path $sourceFolder "converted"
    if (-not (Test-Path $outputDir)) {
        Write-Host "Création du dossier de sortie : $outputDir"
        New-Item -Path $outputDir -ItemType Directory | Out-Null
    }

    $successCount = 0
    $failCount = 0

    $useTurbo = Read-Host "Activer le Mode Turbo (encodage parallèle) ? [o/N]"
    if ($useTurbo.ToLower() -eq 'o') {
        # --- Mode Turbo (Parallèle) ---
        $maxConcurrentJobs = [System.Environment]::ProcessorCount
        Write-Host "Mode Turbo activé. Lancement de jusqu'à $maxConcurrentJobs conversions en parallèle." -ForegroundColor Green

        $runningJobs = @()
        $filesQueue = [System.Collections.Generic.Queue[System.IO.FileInfo]]::new($filesToConvert)
        $totalFiles = $filesToConvert.Count
        $processedCount = 0

        while ($processedCount -lt $totalFiles) {
            while ($runningJobs.Count -lt $maxConcurrentJobs -and $filesQueue.Count -gt 0) {
                $file = $filesQueue.Dequeue()
                $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
                $suggestedFileName = "${sourceBaseName}_${selectedPresetName}.${preset.container}"
                $outputPath = Join-Path $outputDir $suggestedFileName

                if ($file.DirectoryName -eq $outputDir) {
                    Write-Warning "Le fichier '$($file.Name)' est déjà dans le dossier de sortie. Ignoré."
                    $processedCount++
                    continue
                }

                $scriptBlock = {
                    param($sourcePath, $outPath, $currentPreset)
                    $ffmpegArgs = @('-i', $sourcePath, '-c:v', $currentPreset.vcodec, '-preset', $currentPreset.preset, '-pix_fmt', $currentPreset.pix_fmt)
                    if ($currentPreset.PSObject.Properties['crf']) { $ffmpegArgs += @('-crf', $currentPreset.crf) }
                    if ($currentPreset.PSObject.Properties['cq']) { $ffmpegArgs += @('-cq', $currentPreset.cq) }
                    if ($currentPreset.acodec -eq 'copy') { $ffmpegArgs += @('-c:a', 'copy') } else { $ffmpegArgs += @('-c:a', $currentPreset.acodec, '-b:a', $currentPreset.abitrate) }
                    if ($currentPreset.extra_args) { $ffmpegArgs += $currentPreset.extra_args.Split(' ') }
                    $ffmpegArgs += $outPath
                    & ffmpeg -y -v error -stats $ffmpegArgs
                    return @{ Success = ($LASTEXITCODE -eq 0); FileName = $sourcePath }
                }

                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $file.FullName, $outputPath, $preset
                $job.Name = $file.Name
                $runningJobs += $job
                Write-Host "Lancement de la conversion pour $($job.Name)..."
            }

            $finishedJob = Wait-Job -Job $runningJobs -Any
            $jobResult = Receive-Job -Job $finishedJob

            $processedCount++
            Write-Host "($processedCount/$totalFiles) Tâche terminée pour '$($finishedJob.Name)'." -ForegroundColor Gray

            if ($jobResult.Success) { $successCount++ } else { $failCount++; Write-Warning "La conversion de $($jobResult.FileName) a échoué." }

            Remove-Job -Job $finishedJob
            $runningJobs = $runningJobs | Where-Object { $_.Id -ne $finishedJob.Id }
            Start-Sleep -Milliseconds 100
        }
    } else {
        # --- Mode Séquentiel ---
        for ($i = 0; $i -lt $filesToConvert.Count; $i++) {
            $file = $filesToConvert[$i]
            Write-Host "------------------------------------------------------------"
            Write-Host "Conversion du fichier $($i+1)/$($filesToConvert.Count): $($file.Name)" -ForegroundColor White

            $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
            $suggestedFileName = "${sourceBaseName}_${selectedPresetName}.${preset.container}"
            $outputPath = Join-Path $outputDir $suggestedFileName

            if ($file.DirectoryName -eq $outputDir) {
                Write-Warning "Le fichier '$($file.Name)' est déjà dans le dossier de sortie. Il est ignoré."
                continue
            }

            if (Invoke-FFmpegConversion -SourcePath $file.FullName -OutputPath $outputPath -Preset $preset) {
                $successCount++
            } else {
                $failCount++
            }
        }
    }

    # --- Résumé ---
    Write-Host "------------------------------------------------------------"
    Write-Host "Traitement par lots terminé." -ForegroundColor Green
    Write-Host "Succès : $successCount"
    Write-Host "Échecs : $failCount" -ForegroundColor Red

    Show-ToastNotification -Title "Traitement par Lots Terminé" -Message "Succès: $successCount, Échecs: $failCount."
}

# =================================================================
# --- NOTIFICATIONS & FINALISATION ---
# =================================================================

function Install-ToastModuleIfMissing {
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Write-Host "Module 'BurntToast' pour les notifications manquant. Installation..." -ForegroundColor Yellow
        try {
            # Force confirmation to avoid prompts in non-interactive environments
            Install-Module -Name BurntToast -Scope CurrentUser -Force -Confirm:$false
            Write-Host "Module 'BurntToast' installé." -ForegroundColor Green
        } catch {
            Write-Warning "Impossible d'installer 'BurntToast'. Les notifications de bureau seront désactivées."
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
# --- OUTILS SUPPLÉMENTAIRES ---
# =================================================================

function Create-AnimatedGif {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath
    )

    Write-Host ""
    Write-Host "--- Création de GIF Animé ---"

    # --- Collecte des paramètres ---
    $startTime = Read-Host "Entrez le moment de début (ex: 00:01:23)"
    if ($startTime -notmatch '^\d{2}:\d{2}:\d{2}(\.\d+)?$') { Write-Error "Format de temps invalide."; return }

    $duration = Read-Host "Entrez la durée en secondes (ex: 3.5)"
    if (-not ([double]::TryParse($duration, [ref]$null))) { Write-Error "Durée invalide. Utilisez un nombre."; return }

    $fps = Read-Host "Entrez les images par seconde (ex: 15) [Défaut: 15]"
    if (-not $fps) { $fps = 15 }

    $width = Read-Host "Entrez la largeur en pixels (ex: 480) [Défaut: 480]"
    if (-not $width) { $width = 480 }

    # --- Définition des chemins ---
    $sourceDir = [System.IO.Path]::GetDirectoryName($SourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $outputPath = Join-Path $sourceDir "${sourceBaseName}_${startTime.Replace(':', '-')}_${duration}s.gif"
    $palettePath = Join-Path ([System.IO.Path]::GetTempPath()) "palette.png"

    try {
        # --- Étape 1: Génération de la palette ---
        Write-Host "Étape 1/2: Analyse et génération de la palette de couleurs..." -ForegroundColor Cyan
        $vfPalette = "fps=$fps,scale=$width:-1:flags=lanczos,palettegen"
        $ffmpegPaletteArgs = @('-y', '-ss', $startTime, '-t', $duration, '-i', $SourcePath, '-vf', $vfPalette, $palettePath)

        & ffmpeg $ffmpegPaletteArgs

        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg a échoué lors de la génération de la palette."
        }

        # --- Étape 2: Création du GIF avec la palette ---
        Write-Host "Étape 2/2: Création du GIF..." -ForegroundColor Cyan
        $filterComplex = "fps=$fps,scale=$width:-1:flags=lanczos[x];[x][1:v]paletteuse"
        $ffmpegGifArgs = @('-ss', $startTime, '-t', $duration, '-i', $SourcePath, '-i', $palettePath, '-filter_complex', $filterComplex, $outputPath)

        & ffmpeg -y $ffmpegGifArgs

        if ($LASTEXITCODE -eq 0) {
            Write-Host "GIF créé avec succès !" -ForegroundColor Green
            Write-Host $outputPath
        } else {
            throw "FFmpeg a échoué lors de la création du GIF."
        }
    } catch {
        Write-Error $_.Exception.Message
    } finally {
        # --- Nettoyage ---
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
    Write-Host "--- Création de Miniature ---"
    $timestamp = Read-Host "Entrez le moment pour la capture (ex: 00:01:23) [Défaut: 00:00:10]"
    if (-not $timestamp) { $timestamp = '00:00:10' }

    # Simple validation regex pour le format HH:MM:SS ou HH:MM:SS.ms
    if ($timestamp -notmatch '^\d{2}:\d{2}:\d{2}(\.\d+)?$') {
        Write-Error "Format de temps invalide. Utilisez HH:MM:SS."
        return
    }

    $sourceDir = [System.IO.Path]::GetDirectoryName($SourcePath)
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $outputPath = Join-Path $sourceDir "${sourceBaseName}_thumbnail.jpg"

    Write-Host "Création de la miniature vers '$outputPath'..." -ForegroundColor Cyan

    $ffmpegArgs = @(
        '-ss', $timestamp,
        '-i', $SourcePath,
        '-vframes', '1',
        '-q:v', '2', # Qualité JPEG (2-5 est une bonne plage)
        $outputPath
    )

    # L'option -y écrase le fichier de sortie sans demander
    & ffmpeg -y $ffmpegArgs | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Miniature créée avec succès !" -ForegroundColor Green
        Write-Host $outputPath
    } else {
        Write-Error "FFmpeg a échoué lors de la création de la miniature. Vérifiez que le timestamp est valide."
    }
}

function Start-GifOrThumbnailCreation {
    Clear-Host
    Write-Host "--- Créateur de GIF / Miniature ---" -ForegroundColor Yellow

    # 1. Sélection du fichier source (déjà fait si on vient d'un autre menu, mais pour un accès direct c'est nécessaire)
    $sourcePath = Read-Host "Veuillez glisser-déposer le fichier vidéo ici, ou coller le chemin complet"
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        Write-Error "Fichier introuvable ou ce n'est pas un fichier : '$sourcePath'"
        return
    }

    # 2. Sub-menu pour le choix de l'action
    Write-Host ""
    Write-Host "Que voulez-vous créer à partir de '$([System.IO.Path]::GetFileName($sourcePath))' ?"
    Write-Host "[1] Un GIF animé"
    Write-Host "[2] Une miniature (image fixe)"
    $choice = Read-Host "Votre choix"

    switch($choice) {
        '1' { Create-AnimatedGif -SourcePath $sourcePath }
        '2' { Create-Thumbnail -SourcePath $sourcePath }
        default { Write-Warning "Choix invalide." }
    }
}


# =================================================================
# --- SCRIPT PRINCIPAL ---
# =================================================================

function Main {
    # Vérification des dépendances au démarrage
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Error "FFmpeg est introuvable. Veuillez l'installer et l'ajouter au PATH."
        Read-Host "Appuyez sur Entrée pour quitter."; return
    }

    if (-not (Load-Presets)) {
        Read-Host "Appuyez sur Entrée pour quitter."; return
    }

    # Tentative d'installation du module de notifications au premier lancement
    Install-ToastModuleIfMissing

    Start-Sleep -Seconds 1

    # Boucle principale du programme
    while ($true) {
        $choice = Show-MainMenu

        switch ($choice) {
            '1' { Start-SingleFileConversion }
            '2' { Start-BatchConversion }
            '3' { Start-GifOrThumbnailCreation }
            '4' { Manage-Presets }
            'Q' { Write-Host "Au revoir !"; return }
            default { Write-Warning "Choix invalide." }
        }

        Write-Host ""
        Read-Host "Appuyez sur Entrée pour revenir au menu principal..."
    }
}

# --- Lancement du script ---
Main
