# 🎬 Advanced Video Converter Suite

This project provides a powerful and user-friendly suite of tools to convert videos to modern, efficient codecs like **H.265 (HEVC)**, **H.264**, and **AV1**. It leverages your system's hardware for accelerated encoding where possible.

The suite includes:
1.  **🖥️ A Standalone GUI App:** A feature-rich, cross-platform application for converting batches of video files with advanced options.
2.  **🔌 A Premiere Pro Plugin:** A panel that integrates directly into Adobe Premiere Pro for one-click sequence conversion.

---

## ⚙️ 1. Prerequisite: Installing FFmpeg

**Both tools require FFmpeg to be installed on your system and accessible from your system's PATH.** FFmpeg is the core engine that performs the video conversions.

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
---
---

# 🎬 Suite de Conversion Vidéo Avancée

Ce projet fournit une suite d'outils puissants et conviviaux pour convertir des vidéos vers des codecs modernes et efficaces comme le **H.265 (HEVC)**, **H.264** et **AV1**. Il tire parti du matériel de votre système pour l'encodage accéléré lorsque cela est possible.

La suite inclut :
1.  **🖥️ Une Application de Bureau Autonome :** Une application multiplateforme riche en fonctionnalités pour convertir des lots de fichiers vidéo avec des options avancées.
2.  **🔌 Un Plugin Premiere Pro :** Un panneau qui s'intègre directement dans Adobe Premiere Pro pour une conversion en un clic de la séquence active.

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
