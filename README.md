<div align="center">
  <p>
    <b><a href="#-advanced-video-converter-suite-en">English</a></b>
    &nbsp;&nbsp;|&nbsp;&nbsp;
    <b><a href="#-suite-de-conversion-vidéo-avancée-fr">Français</a></b>
  </p>
</div>

# 🎬 Advanced Video Converter Suite (EN)

This project provides a powerful and user-friendly suite of tools to convert videos to modern, efficient codecs like **H.265 (HEVC)**, **H.264**, and **AV1**. It leverages your system's hardware for accelerated encoding where possible.

The suite includes:
1.  **🖥️ A Standalone GUI App:** A feature-rich, cross-platform application for converting batches of video files with advanced options.
2.  **🔌 A Premiere Pro Plugin:** A panel that integrates directly into Adobe Premiere Pro for one-click sequence conversion.
3.  **🦾 A PowerShell CLI Tool:** A powerful command-line script for advanced users, featuring batch processing, parallel encoding, and more.

---

## ⚙️ 1. Prerequisite: Installing FFmpeg

**All tools require FFmpeg to be installed on your system and accessible from your system's PATH.** FFmpeg is the core engine that performs the video conversions.

-   **Windows:** Download a build from [ffmpeg.org](https://ffmpeg.org/download.html#build-windows) (e.g., from `gyan.dev`) and add the `bin` folder to your system's `PATH` environment variable.
-   **macOS:** The easiest method is using [Homebrew](https://brew.sh/): `brew install ffmpeg`.
-   **Linux:** Use your distribution's package manager, e.g., `sudo apt-get install ffmpeg`.
---

## 🖥️ 2. Standalone GUI App

The standalone app provides a robust interface for converting multiple files with fine-grained control.

### ✨ Features
-   **🗂️ File Queue:** Add multiple files or entire folders to a conversion queue.
-   **📂 Custom Destination:** Choose a specific folder for your converted files.
-   **🎞️ Codec Selection:** Convert to H.265, H.264, or the next-gen AV1 codec.
-   **🚀 Hardware Acceleration:** Automatically detects and offers hardware encoding (**NVIDIA NVENC**, **Intel QSV**, **Apple VideoToolbox**) if your system and FFmpeg build support it.
-   **📊 Quality Control:** Choose between **Constant Quality (CRF)** for consistent visual quality or **Constant Bitrate (CBR)** for predictable file sizes.
-   **🔊 Audio Options:** Copy the audio track directly for maximum speed or re-encode it to efficient **AAC**.
-   **🌙 Shutdown When Complete:** Automatically shut down your computer after the queue is finished.

### ▶️ How to Run
1.  Ensure you have **Python 3** installed.
2.  Navigate to the project's root directory in your terminal.
3.  Run the application with:
    ```bash
    python3 standalone_app/app.py
    ```
    
### 📋 How to Use
1.  **Populate the Queue:** Use **"Add File(s)"** or **"Add Folder"** to add videos to the list.
2.  **Choose Destination:** Click **"Browse..."** to select a folder for the output files.
3.  **Set Encoding Options:** Select your desired video codec, hardware acceleration, quality mode, and audio settings.
4.  **Start Conversion:** Click **"Start Conversion"**. The progress of the current file will be displayed.

---

## 🔌 3. Premiere Pro Plugin

The plugin provides a convenient panel directly within Premiere Pro to quickly export and convert the active sequence.

### ⚠️ CRITICAL Prerequisite: Encoder Preset
The plugin now uses a **real export** process. To work, it **requires a high-quality Adobe Media Encoder preset file** named `master_preset.epr`. You must create this file and place it in the correct location.

#### How to Create and Place the `.epr` File:
1.  ➡️ **Open Adobe Media Encoder.**
2.  ➕ In the **"Preset Browser"** panel, click the **`+`** icon and select **`Create Encoding Preset`**.
3.  ⚙️ Configure the preset for a **high-quality, intermediate format**:
    -   **Format:** `QuickTime`
    -   **Video Codec:** `Apple ProRes 422 HQ` or `GoPro CineForm`. These are ideal for preserving quality before the final H.265 conversion. **Do not** choose H.265 or H.264 here.
4.  💾 Give the preset a name (e.g., "MyProResMaster") and click `OK`.
5.  🔎 **Find the `.epr` file:** Right-click your new preset in the Preset Browser and select **`Reveal Preset File`**.
6.  📋 **Copy and Rename:** Copy this `.epr` file, navigate to the plugin's installation directory, and paste it inside the **`/host`** subfolder. Rename the file to exactly **`master_preset.epr`**.

### 🛠️ How to Install the Plugin

1.  Copy the entire `premiere_pro_plugin` folder into the Adobe CEP `extensions` directory:
    -   **Windows:** `C:\Program Files (x86)\Common Files\Adobe\CEP\extensions\`
    -   **macOS:** `/Library/Application Support/Adobe/CEP/extensions/`

### 📋 How to Use
1.  After installing, **restart Premiere Pro**.
2.  Go to `Window` -> `Extensions` -> `H.265 Converter` to open the panel.
3.  Make sure the sequence you want to export is **active**.
4.  Choose your H.265 encoding options (CRF or CBR).
5.  Click **"Start Export"**. The plugin will:
    a.  First, export a high-quality master file using your `master_preset.epr`. **This may take time.**
    b.  Second, automatically convert that master file to H.265. The final file will be saved in your project's directory.

---

## 🦾 4. PowerShell Command-Line Tool

For users who prefer a powerful, keyboard-driven interface, the suite includes `video-converter-v2.ps1`, a feature-rich command-line tool for advanced conversion tasks.

### ✨ Features
-   **⌨️ Interactive Menu:** A simple and fast menu-driven interface that runs in any terminal.
-   **📝 JSON Presets:** Easily define and manage your own encoding settings in the `presets.json` file.
-   **Single File & Batch Mode:** Convert a single file or an entire folder of videos.
-   **🚀 Turbo Mode:** When converting a folder, you can enable parallel encoding to process multiple files at once, dramatically speeding up the workflow on multi-core CPUs.
-   **🖼️ GIF & Thumbnail Creator:** A built-in utility to quickly create a high-quality animated GIF from a video clip or extract a still thumbnail image.
-   **🔔 Desktop Notifications:** The script provides native desktop notifications on Windows and Linux upon completion of long tasks (requires the `BurntToast` module, which it will try to install).

### ▶️ How to Run
1.  Ensure you have **PowerShell** (v5.1 or newer) installed.
2.  Navigate to the project's root directory in your terminal.
3.  Run the script with:
    ```bash
    pwsh ./video-converter-v2.ps1
    ```

### 📋 How to Use
1.  Launch the script.
2.  The main menu will appear. Choose an option:
    -   **[1] Convert a single file:** You will be prompted to provide a file path and choose a preset.
    -   **[2] Convert a folder:** You will be prompted for a folder path and a preset. You can then choose to enable "Turbo Mode".
    -   **[3] Create GIF / Thumbnail:** A sub-menu will guide you through creating a GIF or thumbnail from a source video.
    -   **[4] Manage Presets:** Lists the currently available presets from `presets.json`.
3.  Follow the on-screen prompts. All output files are placed in a `converted` sub-directory created within the source folder.
    
---
---

# 🎬 Suite de Conversion Vidéo Avancée (FR)

Ce projet fournit une suite d'outils puissants et conviviaux pour convertir des vidéos vers des codecs modernes et efficaces comme le **H.265 (HEVC)**, **H.264** et **AV1**. Il tire parti du matériel de votre système pour l'encodage accéléré lorsque cela est possible.

La suite inclut :
1.  **🖥️ Une Application de Bureau Autonome :** Une application multiplateforme riche en fonctionnalités pour convertir des lots de fichiers vidéo avec des options avancées.
2.  **🔌 Un Plugin Premiere Pro :** Un panneau qui s'intègre directement dans Adobe Premiere Pro pour une conversion en un clic de la séquence active.
3.  **🦾 Un Outil en Ligne de Commande PowerShell :** Un script puissant pour les utilisateurs avancés, avec traitement par lots, encodage parallèle, et plus encore.

---

## ⚙️ 1. Prérequis : Installation de FFmpeg

**Les deux outils nécessitent que FFmpeg soit installé sur votre système et accessible depuis le PATH.** FFmpeg est le moteur principal qui effectue les conversions vidéo.

-   **Windows :** Téléchargez une version depuis [ffmpeg.org](https://ffmpeg.org/download.html#build-windows) (par exemple, depuis `gyan.dev`) et ajoutez le dossier `bin` à votre variable d'environnement `PATH`.
-   **macOS :** La méthode la plus simple est d'utiliser [Homebrew](https://brew.sh/) : `brew install ffmpeg`.
-   **Linux :** Utilisez le gestionnaire de paquets de votre distribution, par exemple, `sudo apt-get install ffmpeg`.

---

## 🖥️ 2. Application de Bureau Autonome

L'application autonome fournit une interface robuste pour convertir plusieurs fichiers avec un contrôle précis.

### ✨ Fonctionnalités
-   **🗂️ File d'attente :** Ajoutez plusieurs fichiers ou des dossiers entiers à une file de conversion.
-   **📂 Destination Personnalisée :** Choisissez un dossier spécifique pour vos fichiers convertis.
-   **🎞️ Sélection du Codec :** Convertissez en H.265, H.264, ou le codec de nouvelle génération AV1.
-   **🚀 Accélération Matérielle :** Détecte et propose automatiquement l'encodage matériel (**NVIDIA NVENC**, **Intel QSV**, **Apple VideoToolbox**) si votre système et votre version de FFmpeg le supportent.
-   **📊 Contrôle de la Qualité :** Choisissez entre une **Qualité Constante (CRF)** pour une qualité visuelle homogène ou un **Débit Binaire Constant (CBR)** pour des tailles de fichier prévisibles.
-   **🔊 Options Audio :** Copiez directement la piste audio pour une vitesse maximale ou ré-encodez-la en **AAC**, un format efficace.
-   **🌙 Éteindre l'ordinateur :** Éteignez automatiquement votre ordinateur une fois la file d'attente terminée.

### ▶️ Comment Lancer
1.  Assurez-vous que **Python 3** est installé.
2.  Naviguez jusqu'au répertoire racine du projet dans votre terminal.
3.  Lancez l'application avec :
    ```bash
    python3 standalone_app/app.py
    ```
    
### 📋 Comment Utiliser
1.  **Remplissez la file d'attente :** Utilisez **"Add File(s)"** ou **"Add Folder"** pour ajouter des vidéos à la liste.
2.  **Choisissez la Destination :** Cliquez sur **"Browse..."** pour sélectionner un dossier pour les fichiers de sortie.
3.  **Réglez les Options d'Encodage :** Sélectionnez le codec vidéo, l'accélération matérielle, le mode de qualité et les paramètres audio souhaités.
4.  **Lancez la Conversion :** Cliquez sur **"Start Conversion"**. La progression du fichier actuel sera affichée.

---

## 🔌 3. Plugin Premiere Pro

Le plugin fournit un panneau pratique directement dans Premiere Pro pour exporter et convertir rapidement la séquence active.

### ⚠️ Prérequis CRITIQUE : Préréglage d'Encodage
Le plugin utilise désormais un **processus d'exportation réel**. Pour fonctionner, il **nécessite un fichier de préréglage Adobe Media Encoder de haute qualité** nommé `master_preset.epr`. Vous devez créer ce fichier et le placer au bon endroit.

#### Comment Créer et Placer le Fichier `.epr` :
1.  ➡️ **Ouvrez Adobe Media Encoder.**
2.  ➕ Dans le panneau **"Explorateur de préconfigurations"**, cliquez sur l'icône **`+`** et sélectionnez **`Créer une préconfiguration d'encodage`**.
3.  ⚙️ Configurez le préréglage pour un **format intermédiaire de haute qualité** :
    -   **Format :** `QuickTime`
    -   **Codec Vidéo :** `Apple ProRes 422 HQ` ou `GoPro CineForm`. Ces formats sont idéaux pour préserver la qualité avant la conversion finale en H.265. **Ne choisissez pas** H.265 ou H.264 ici.
4.  💾 Donnez un nom au préréglage (ex: "MonMasterProRes") et cliquez sur `OK`.
5.  🔎 **Trouvez le fichier `.epr` :** Faites un clic droit sur votre nouvelle préconfiguration dans l'explorateur et sélectionnez **`Afficher le fichier de préconfiguration`**.
6.  📋 **Copiez et Renommez :** Copiez ce fichier `.epr`, naviguez jusqu'au répertoire d'installation du plugin, et collez-le dans le sous-dossier **`/host`**. Renommez le fichier en exactement **`master_preset.epr`**.

### 🛠️ Comment Installer le Plugin

1.  Copiez l'intégralité du dossier `premiere_pro_plugin` dans le répertoire `extensions` d'Adobe CEP :
    -   **Windows :** `C:\Program Files (x86)\Common Files\Adobe\CEP\extensions\`
    -   **macOS :** `/Library/Application Support/Adobe/CEP/extensions/`

### 📋 Comment Utiliser
1.  Après l'installation, **redémarrez Premiere Pro**.
2.  Allez dans `Fenêtre` -> `Extensions` -> `H.265 Converter` pour ouvrir le panneau.
3.  Assurez-vous que la séquence que vous souhaitez exporter est **active**.
4.  Choisissez vos options d'encodage H.265 (CRF ou CBR).
5.  Cliquez sur **"Start Export"**. Le plugin va :
    a.  D'abord, exporter un fichier master de haute qualité en utilisant votre `master_preset.epr`. **Cela peut prendre du temps.**
    b.  Ensuite, convertir automatiquement ce fichier master en H.265. Le fichier final sera sauvegardé dans le répertoire de votre projet.

---

## 🦾 4. Outil en Ligne de Commande PowerShell

Pour les utilisateurs qui préfèrent une interface puissante pilotée par le clavier, la suite inclut `video-converter-v2.ps1`, un outil en ligne de commande riche en fonctionnalités pour les tâches de conversion avancées.

### ✨ Fonctionnalités
-   **⌨️ Menu Interactif :** Une interface simple et rapide via un menu qui s'exécute dans n'importe quel terminal.
-   **📝 Préréglages JSON :** Définissez et gérez facilement vos propres paramètres d'encodage dans le fichier `presets.json`.
-   **Fichier Unique & Mode Dossier :** Convertissez un seul fichier ou un dossier entier de vidéos.
-   **🚀 Mode Turbo :** Lors de la conversion d'un dossier, vous pouvez activer l'encodage parallèle pour traiter plusieurs fichiers à la fois, accélérant considérablement le travail sur les processeurs multi-cœurs.
-   **🖼️ Créateur de GIF & Miniatures :** Un utilitaire intégré pour créer rapidement un GIF animé de haute qualité à partir d'un clip vidéo ou pour extraire une image fixe (miniature).
-   **🔔 Notifications de Bureau :** Le script envoie des notifications de bureau natives sur Windows et Linux à la fin des tâches longues (nécessite le module `BurntToast`, qu'il essaiera d'installer).

### ▶️ Comment Lancer
1.  Assurez-vous que **PowerShell** (v5.1 ou plus récent) est installé.
2.  Naviguez jusqu'au répertoire racine du projet dans votre terminal.
3.  Lancez le script avec :
    ```bash
    pwsh ./video-converter-v2.ps1
    ```

### 📋 Comment Utiliser
1.  Lancez le script.
2.  Le menu principal apparaîtra. Choisissez une option :
    -   **[1] Convertir un fichier unique :** Il vous sera demandé de fournir un chemin de fichier et de choisir un préréglage.
    -   **[2] Convertir un dossier :** Il vous sera demandé un chemin de dossier et un préréglage. Vous pourrez ensuite choisir d'activer le "Mode Turbo".
    -   **[3] Créer un GIF / Miniature :** Un sous-menu vous guidera pour créer un GIF ou une miniature à partir d'une vidéo source.
    -   **[4] Gérer les préréglages :** Liste les préréglages actuellement disponibles depuis `presets.json`.
3.  Suivez les instructions à l'écran. Tous les fichiers de sortie sont placés dans un sous-dossier `converted` créé dans le dossier source.
