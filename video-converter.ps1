#requires -Version 5.1
<#
.SYNOPSIS
Script PowerShell interactif pour convertir des fichiers vidéo avec FFmpeg.

.DESCRIPTION
Ce script fournit une interface conviviale en ligne de commande pour utiliser FFmpeg.
- Sélection des fichiers source et destination via les boîtes de dialogue natives de Windows.
- Affiche les métadonnées de la vidéo source (format, durée, codecs, résolution, bitrate).
- Permet de choisir le conteneur (MP4/MOV/MKV), le codec vidéo (H.264/H.265), et l'encodeur (NVENC si disponible, sinon CPU).
- Propose une échelle de qualité simplifiée de 1 à 10, qui est mappée sur les paramètres techniques de FFmpeg (CRF pour le CPU, CQ pour NVENC).
- Gère l'audio (conversion en AAC 192k ou copie directe) et les sous-titres (désactivés ou convertis/copiés).
- Affiche une barre de progression détaillée pendant l'encodage (% / temps écoulé / ETA / vitesse / bitrate / etc.).

.REQUIREMENTS
- Windows PowerShell 5.1 ou supérieur.
- FFmpeg et FFprobe doivent être installés et accessibles via le PATH du système.

.NOTES
Version corrigée et améliorée. Les erreurs de syntaxe (fonctions dupliquées) et les problèmes de gestion des chemins avec espaces ont été résolus.
#>

# --- Configuration Stricte et Encodage de la Console ---
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# S'assure que la console affiche correctement les caractères spéciaux (UTF-8)
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# --- Fonctions Utilitaires ---

function Add-WinForms {
    # Charge l'assembly nécessaire pour afficher les boîtes de dialogue graphiques.
    # Si cela échoue (par ex. sur une version Core sans support), on basculera en mode texte.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return $true
    } catch {
        Write-Warning 'Impossible de charger System.Windows.Forms. Le script basculera en saisie console.'
        return $false
    }
}

function Show-OpenFileDialog {
    param(
        [string]$Title = 'Sélectionner le fichier vidéo source',
        [string]$Filter = 'Fichiers vidéo|*.mkv;*.mp4;*.mov;*.m4v;*.avi;*.ts;*.m2ts;*.webm|Tous les fichiers|*.*'
    )
    if (-not (Add-WinForms)) { return Read-Host "Veuillez entrer le chemin complet du fichier source" }
    
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = $Title
    $ofd.Filter = $Filter
    $ofd.Multiselect = $false
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $ofd.FileName
    }
    throw 'Sélection du fichier source annulée par l`utilisateur.'
}

function Show-SaveFileDialog {
    param(
        [string]$Title = 'Choisir le fichier de sortie',
        [string]$DefaultExt = 'mp4',
        [string]$Filter = 'Fichier MP4|*.mp4|Fichier MOV|*.mov|Fichier MKV|*.mkv|Tous les fichiers|*.*',
        [string]$SuggestedName = 'output.mp4'
    )
    if (-not (Add-WinForms)) { return Read-Host "Veuillez entrer le chemin complet du fichier de sortie (avec extension)" }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = $Title
    $sfd.DefaultExt = $DefaultExt
    $sfd.Filter = $Filter
    $sfd.FileName = $SuggestedName
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $sfd.FileName
    }
    throw 'Sélection du fichier de sortie annulée par l`utilisateur.'
}

function Invoke-FfprobeJson {
    param([Parameter(Mandatory=$true)][string]$Path)
    # Exécute ffprobe pour obtenir les métadonnées au format JSON, plus facile à parser.
    # CORRIGÉ : Ajout de guillemets autour de $Path pour gérer les espaces.
    $jsonOutput = & ffprobe -v error -hide_banner -print_format json -show_format -show_streams -- "$Path"
    if (-not $jsonOutput) { throw "ffprobe n'a retourné aucune donnée pour le fichier. Est-ce un fichier vidéo valide ?" }
    return $jsonOutput | ConvertFrom-Json
}

function Format-Duration {
    param([double]$Seconds)
    if ($Seconds -le 0) { return '??:??:??' }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    # Gère les durées supérieures à 24 heures.
    return ('{0:00}:{1:00}:{2:00}' -f ([int]$ts.TotalHours), $ts.Minutes, $ts.Seconds)
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GiB' -f ($Bytes / 1GB)) }
    elseif ($Bytes -ge 1MB) { return ('{0:N1} MiB' -f ($Bytes / 1MB)) }
    elseif ($Bytes -ge 1KB) { return ('{0:N0} KiB' -f ($Bytes / 1KB)) }
    else { return ('{0} B' -f $Bytes) }
}

function Format-Bitrate {
    param([double]$Bps)
    if ($Bps -le 0) { return 'N/A' }
    # Convertit les bits/seconde en Mégabits/seconde.
    $mbps = $Bps / 1e6
    return ('{0:N2} Mb/s' -f $mbps)
}

function Fraction-ToDouble {
    param([string]$Fraction)
    if (-not $Fraction -or $Fraction -eq '0/0') { return 0.0 }
    $parts = $Fraction.Split('/')
    if ($parts.Count -ne 2 -or [double]$parts[1] -eq 0) { return 0.0 }
    return [double]$parts[0] / [double]$parts[1]
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$DefaultIndex = 0
    )
    Write-Host ''
    Write-Host $Prompt -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ('  [{0}] {1}' -f ($i + 1), $Options[$i])
    }
    $defaultChoice = $DefaultIndex + 1
    do {
        $input = Read-Host ("Votre choix (1-{0}) [Défaut: {1}]" -f $Options.Count, $defaultChoice)
        if (-not $input) { return $DefaultIndex } # L'utilisateur appuie sur Entrée pour le choix par défaut
        try {
            $selection = [int]$input
            if ($selection -ge 1 -and $selection -le $Options.Count) {
                return $selection - 1
            }
        } catch {
            # L'entrée n'était pas un nombre, la boucle continue
        }
        Write-Warning "Veuillez entrer un nombre valide entre 1 et $($Options.Count)."
    } while ($true)
}

function Map-Quality {
    param(
        [ValidateSet('x264', 'x265', 'h264_nvenc', 'hevc_nvenc')][string]$Encoder,
        [ValidateRange(1, 10)][int]$Level
    )
    # Mappe l'échelle de qualité simple (1-10) à des valeurs CRF/CQ techniques.
    # Des valeurs plus basses signifient une meilleure qualité.
    switch ($Encoder) {
        'x264' { $map = @(16, 17, 18, 19, 20, 21, 22, 24, 26, 28); return @{ mode = 'crf'; value = $map[$Level - 1] } }
        'x265' { $map = @(18, 19, 20, 21, 22, 23, 24, 26, 28, 30); return @{ mode = 'crf'; value = $map[$Level - 1] } }
        'h264_nvenc' { $map = @(18, 19, 20, 21, 22, 23, 24, 25, 26, 27); return @{ mode = 'cq'; value = $map[$Level - 1] } }
        'hevc_nvenc' { $map = @(20, 21, 22, 23, 24, 25, 26, 27, 28, 29); return @{ mode = 'cq'; value = $map[$Level - 1] } }
    }
}

function Detect-Encoders {
    # Détecte les encodeurs matériels disponibles en parsant la sortie de ffmpeg.
    $encodersOutput = & ffmpeg -hide_banner -v error -encoders
    return [PSCustomObject]@{
        h264_nvenc = ($encodersOutput -match 'h264_nvenc\s')
        hevc_nvenc = ($encodersOutput -match 'hevc_nvenc\s')
        # On pourrait aussi ajouter la détection pour Intel Quick Sync (qsv) et AMD (amf) ici.
    }
}

function Run-FFmpegWithProgress {
    param(
        [string[]]$Arguments,
        [double]$DurationSeconds
    )
    # CORRIGÉ : Remplacement de la lecture de sortie synchrone par un modèle asynchrone
    # pour éviter les blocages (deadlocks) lorsque FFmpeg écrit sur le flux d'erreur.

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'ffmpeg'
    $psi.Arguments = ($Arguments + @('-progress', 'pipe:1', '-nostats')) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    # Utilisation de variables de portée 'script' pour qu'elles soient accessibles
    # depuis les blocs d'action des gestionnaires d'événements.
    $script:ffmpegState = @{}
    $script:ffmpegDurationUs = [long]($DurationSeconds * 1000000)
    $script:ffmpegErrorOutput = [System.Text.StringBuilder]::new()
    
    $outputAction = {
        param([object]$sender, [System.Diagnostics.DataReceivedEventArgs]$e)
        
        if ($null -eq $e.Data -or -not $e.Data.Contains('=')) { return }
        
        $line = $e.Data
        $key, $value = $line.Split('=', 2)
        $script:ffmpegState[$key.Trim()] = $value.Trim()

        if ($key.Trim() -eq 'out_time_us' -or $key.Trim() -eq 'progress') {
            $outUs = if ($script:ffmpegState.ContainsKey('out_time_us')) { [long]$script:ffmpegState['out_time_us'] } else { 0 }
            $pct = if ($script:ffmpegDurationUs -gt 0) { [Math]::Min(100, [Math]::Max(0, ($outUs * 100.0 / $script:ffmpegDurationUs))) } else { 0 }
            
            # CORRIGÉ : Récupération de la durée via $event.MessageData
            $durationSecForFormatting = $event.MessageData
            
            $fps = if ($script:ffmpegState.ContainsKey('fps')) { $script:ffmpegState['fps'] } else { '0.0' }
            $speed = if ($script:ffmpegState.ContainsKey('speed')) { $script:ffmpegState['speed'] } else { '0x' }
            $bitrate = if ($script:ffmpegState.ContainsKey('bitrate')) { $script:ffmpegState['bitrate'] -replace 'bits/s', 'b/s' } else { 'N/A' }
            $totalSize = if ($script:ffmpegState.ContainsKey('total_size')) { [long]$script:ffmpegState['total_size'] } else { 0 }

            $outTimeSpan = [TimeSpan]::FromMilliseconds($outUs / 1000.0)
            $etaText = ''
            if ($speed -match '([0-9\.]+)x' -and $matches[1] -ne '0.0') {
                $speedNum = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
                if ($speedNum -gt 0 -and $script:ffmpegDurationUs -gt $outUs) {
                    $remainingSeconds = (($script:ffmpegDurationUs - $outUs) / 1000000.0) / $speedNum
                    $eta = [TimeSpan]::FromSeconds([Math]::Max(0, $remainingSeconds))
                    $etaText = (' ETA {0:hh\:mm\:ss}' -f $eta)
                }
            }

            $progressLine = ('[{0,5:N1}%] {1:hh\:mm\:ss} / {2} | FPS: {3} | Vitesse: {4} | Bitrate: {5} | Taille: {6}' -f
                $pct, $outTimeSpan, (Format-Duration $durationSecForFormatting), $fps, $speed, $bitrate, (Format-Size $totalSize))

            # Remplacé Write-Host par [Console]::Write pour une sortie plus fiable depuis un gestionnaire d'événements asynchrone.
            [Console]::Write("`r$progressLine$etaText  ")
        }
    }
    
    $errorAction = {
        param([object]$sender, [System.Diagnostics.DataReceivedEventArgs]$e)
        if ($e.Data) {
            [void]$script:ffmpegErrorOutput.AppendLine($e.Data)
        }
    }

    # CORRIGÉ : Remplacement de -ArgumentList par -MessageData
    $stdoutEvent = Register-ObjectEvent -InputObject $process -EventName 'OutputDataReceived' -Action $outputAction -MessageData $DurationSeconds
    $stderrEvent = Register-ObjectEvent -InputObject $process -EventName 'ErrorDataReceived' -Action $errorAction

    $finalErrorOutput = ''
    try {
        [void]$process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        $process.WaitForExit()
        $finalErrorOutput = $script:ffmpegErrorOutput.ToString()
    } finally {
        Unregister-Event -SourceIdentifier $stdoutEvent.Name
        Unregister-Event -SourceIdentifier $stderrEvent.Name
        Remove-Variable -Name 'ffmpegState', 'ffmpegDurationUs', 'ffmpegErrorOutput' -Scope Script -ErrorAction SilentlyContinue
    }

    Write-Host '' # Nouvelle ligne après la barre de progression
    if ($process.ExitCode -ne 0) {
        throw "FFmpeg a échoué avec le code de sortie $($process.ExitCode).`nErreur rapportée :`n$finalErrorOutput"
    }
}


# ================================
# --- SCRIPT PRINCIPAL (MAIN) ---
# ================================
try {
    # --- Vérification des prérequis ---
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw 'FFmpeg est introuvable. Veuillez l`installer et l`ajouter au PATH.' }
    if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) { throw 'FFprobe est introuvable. Veuillez l`installer et l`ajouter au PATH.' }

    # --- Sélection et Analyse du Fichier ---
    $inPath = Show-OpenFileDialog
    Write-Host "Analyse du fichier '$([System.IO.Path]::GetFileName($inPath))'..." -ForegroundColor Yellow
    $probe = Invoke-FfprobeJson -Path $inPath

    $format = $probe.format
    $videoStream = $probe.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    $audioStream = $probe.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1

    if (-not $videoStream) { throw "Aucun flux vidéo trouvé dans le fichier." }

    $durationSec = 0
    if ($format.duration) { $durationSec = [double]::Parse($format.duration, [System.Globalization.CultureInfo]::InvariantCulture) }

    $totalBitrate = 0
    if ($format.bit_rate) { $totalBitrate = [double]$format.bit_rate }

    # --- Affichage des Métadonnées ---
    Write-Host ''
    Write-Host '--- MÉTADONNÉES DU FICHIER SOURCE ---' -ForegroundColor Green
    Write-Host ("Fichier      : " + $inPath)
    Write-Host ("Format       : " + $format.format_long_name)
    Write-Host ("Durée        : " + (Format-Duration $durationSec))
    $resolution = "$($videoStream.width)x$($videoStream.height)"
    $fps = if ($videoStream.avg_frame_rate) { [Math]::Round((Fraction-ToDouble $videoStream.avg_frame_rate), 2) } else { 'N/A' }
    Write-Host ("Vidéo        : $($videoStream.codec_name), $resolution, $($fps)fps")
    if ($audioStream) {
        Write-Host ("Audio        : $($audioStream.codec_name), $($audioStream.channel_layout), $($audioStream.sample_rate) Hz")
    }
    Write-Host ("Bitrate total: " + (Format-Bitrate $totalBitrate))

    # --- Collecte des Options de Conversion ---
    $containerIdx = Read-Choice 'Choisir le conteneur de sortie' @('MP4 (recommandé)', 'MOV', 'MKV') 0
    $container = @('mp4', 'mov', 'mkv')[$containerIdx]

    $codecIdx = Read-Choice 'Choisir le codec vidéo' @('H.264 (AVC)', 'H.265 (HEVC)') 1
    $codecChoice = @('h264', 'hevc')[$codecIdx]

    $encoders = Detect-Encoders
    $hwAvailable = $false
    if ($codecChoice -eq 'h264' -and $encoders.h264_nvenc) { $hwAvailable = $true }
    if ($codecChoice -eq 'hevc' -and $encoders.hevc_nvenc) { $hwAvailable = $true }

    $encoderOptions = @('Logiciel (CPU x264/x265)')
    if ($hwAvailable) { $encoderOptions = @('Matériel (NVIDIA NVENC)', 'Logiciel (CPU x264/x265)') }
    
    $encoderIdx = Read-Choice "Choisir l'encodeur" $encoderOptions 0
    $useHardware = ($hwAvailable -and $encoderIdx -eq 0)

    $qualityText = @('1 (Qualité maximale, fichier lourd)', '2', '3', '4 (Très bonne qualité)', '5', '6 (Bon équilibre)', '7', '8 (Qualité correcte)', '9', '10 (Fichier léger, qualité réduite)')
    $qualityIdx = Read-Choice 'Choisir un niveau de qualité (1=meilleur, 10=plus léger)' $qualityText 5
    $qualityLevel = $qualityIdx + 1

    $audioIdx = Read-Choice 'Traitement de l`audio' @('Convertir en AAC 192k (recommandé)', 'Copier le flux audio (si compatible)') 0
    $copyAudio = ($audioIdx -eq 1)

    $subtitleIdx = Read-Choice 'Traitement des sous-titres' @('Ignorer les sous-titres', 'Inclure les sous-titres (copie ou conversion)') 0
    $includeSubs = ($subtitleIdx -eq 1)

    # --- Préparation du Nom de Fichier de Sortie ---
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inPath)
    $suggestedName = "${baseName}_converted.${container}"
    $outPath = Show-SaveFileDialog -DefaultExt $container -SuggestedName $suggestedName

    # --- Construction de la Commande FFmpeg ---
    # CORRIGÉ : Les chemins d'entrée/sortie sont mis entre guillemets pour gérer les espaces.
    $ffmpegArgs = @('-y', '-i', "`"$inPath`"")
    
    # Mappage des flux : vidéo 0, premier flux audio, et sous-titres si demandés.
    $ffmpegArgs += @('-map', '0:v:0', '-map', '0:a:0?')
    if ($includeSubs) { $ffmpegArgs += @('-map', '0:s?') } else { $ffmpegArgs += @('-sn') }

    # Paramètres vidéo
    if ($useHardware) {
        $encoderName = if ($codecChoice -eq 'h264') { 'h264_nvenc' } else { 'hevc_nvenc' }
        $qualityParams = Map-Quality -Encoder $encoderName -Level $qualityLevel
        $ffmpegArgs += @('-c:v', $encoderName, '-preset', 'p6', '-rc:v', 'vbr')
        $ffmpegArgs += @("-b:v", "0", "-rc-lookahead", "20") # Mode VBR basé sur la qualité
        $ffmpegArgs += @("-qmin", "0", "-cq", $qualityParams.value, "-qmax", "51")
    } else { # CPU
        $encoderName = if ($codecChoice -eq 'h264') { 'libx264' } else { 'libx265' }
        $cpuEncoderName = if ($codecChoice -eq 'h264') { 'x264' } else { 'x265' }
        $qualityParams = Map-Quality -Encoder $cpuEncoderName -Level $qualityLevel
        $ffmpegArgs += @('-c:v', $encoderName, '-preset', 'medium')
        $ffmpegArgs += @('-' + $qualityParams.mode, $qualityParams.value)
    }
    $ffmpegArgs += @('-pix_fmt', 'yuv420p') # Format de pixel le plus compatible
    if ($codecChoice -eq 'hevc' -and ($container -in @('mp4', 'mov'))) {
        $ffmpegArgs += @('-tag:v', 'hvc1') # Tag pour meilleure compatibilité Apple
    }

    # Paramètres audio
    if ($copyAudio) { $ffmpegArgs += @('-c:a', 'copy') } else { $ffmpegArgs += @('-c:a', 'aac', '-b:a', '192k') }

    # Paramètres sous-titres
    if ($includeSubs) {
        if ($container -in @('mp4', 'mov')) { $ffmpegArgs += @('-c:s', 'mov_text') } # Le format le plus compatible pour MP4/MOV
        else { $ffmpegArgs += @('-c:s', 'copy') } # MKV peut copier la plupart des formats
    }

    # Paramètres conteneur
    if ($container -in @('mp4', 'mov')) { $ffmpegArgs += @('-movflags', '+faststart') }
    
    $ffmpegArgs += @("`"$outPath`"")

    # --- Résumé et Lancement ---
    Write-Host ''
    Write-Host '--- RÉSUMÉ DE LA CONVERSION ---' -ForegroundColor Green
    $encoderLabel = if ($useHardware) { "$encoderName (Matériel)" } else { "$encoderName (CPU)" }
    $qualityLabel = if ($useHardware) { "CQ" } else { "CRF" }
    $audioLabel   = if ($copyAudio) { 'Copie directe' } else { 'AAC 192k' }
    $subsLabel    = if ($includeSubs) { 'Inclus' } else { 'Ignorés' }
    Write-Host ("Sortie       : " + $outPath)
    Write-Host ("Conteneur    : " + $container.ToUpper())
    Write-Host ("Vidéo        : " + $encoderLabel)
    Write-Host ("Qualité      : $qualityLevel/10 ($qualityLabel = $($qualityParams.value))")
    Write-Host ("Audio        : " + $audioLabel)
    Write-Host ("Sous-titres  : " + $subsLabel)
    
    Write-Host ''
    Write-Host 'Lancement de l`encodage...' -ForegroundColor Yellow
    Run-FFmpegWithProgress -Arguments $ffmpegArgs -DurationSeconds $durationSec

    Write-Host ''
    Write-Host 'Conversion terminée avec succès ! ✅' -ForegroundColor Green
    Write-Host "Le fichier est disponible ici : $outPath"

} catch {
    Write-Host ''
    Write-Error "Une erreur critique est survenue : $($_.Exception.Message)"
}