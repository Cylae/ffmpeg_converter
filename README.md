# H.265 Video Converter Suite

This project contains two tools to simplify the process of converting videos to the highly efficient H.265 (HEVC) codec:
1.  **A Standalone GUI App:** A simple, cross-platform application for converting video files or batches of files.
2.  **A Premiere Pro Plugin:** A panel that integrates directly into Adobe Premiere Pro for one-click sequence conversion.

## 1. Prerequisite: Installing FFmpeg

**Both tools require FFmpeg to be installed on your system.** FFmpeg is the powerful engine that performs the video conversions. You must ensure the `ffmpeg` and `ffprobe` executables are available in your system's PATH.

### Windows
1.  Go to the official FFmpeg download page: [https://ffmpeg.org/download.html#build-windows](https://ffmpeg.org/download.html#build-windows)
2.  Download a build from a trusted source (e.g., `gyan.dev` or `BtbN`).
3.  Unzip the downloaded file into a permanent location on your computer, for example, `C:\ffmpeg`.
4.  Add the `bin` directory from your FFmpeg folder (e.g., `C:\ffmpeg\bin`) to your system's `PATH` environment variable. There are many online tutorials for "how to add to PATH in Windows".

### macOS
The easiest way to install FFmpeg on macOS is by using the [Homebrew](https://brew.sh/) package manager.
1.  If you don't have Homebrew, open the Terminal app and install it by following the instructions on their website.
2.  Once Homebrew is installed, simply run the following command in your Terminal:
    ```bash
    brew install ffmpeg
    ```

## 2. Standalone GUI App

The standalone app allows you to convert video files outside of Premiere Pro.

### How to Run
1.  Ensure you have Python 3 installed.
2.  Navigate to the project's root directory in your terminal.
3.  Run the application with the following command:
    ```bash
    python3 standalone_app/app.py
    ```

### How to Use
1.  **Select File(s):** Use "Select Video File" for a single file or "Select Folder (Batch)" to convert all videos in a folder.
2.  **Choose Options:** Select either Constant Quality (CRF) or Constant Bitrate (CBR) and set your desired value.
3.  **Start Export:** Click the "Start Export" button. The converted files will be saved in the same directory as the original files with `_h265` appended to the filename.

## 3. Premiere Pro Plugin

The plugin provides a convenient panel directly within Premiere Pro.

### How to Install
You must manually copy the plugin folder into Premiere Pro's extension directory.
1.  Locate the `premiere_pro_plugin` folder within this project's files.
2.  Copy the entire `premiere_pro_plugin` folder.
3.  Paste it into the correct CEP `extensions` directory for your operating system:
    -   **Windows:** `C:\Program Files (x86)\Common Files\Adobe\CEP\extensions\`
    -   **macOS:** `/Library/Application Support/Adobe/CEP/extensions/` (This is the system-level folder. You may need admin rights. The user-level folder is `~/Library/Application Support/Adobe/CEP/extensions/`).

### How to Use
1.  After installing, restart Premiere Pro.
2.  Go to `Window` -> `Extensions` -> `H.265 Converter` to open the panel.
3.  Make sure the sequence you want to export is active in the timeline.
4.  Choose your encoding options in the panel.
5.  Click "Start Export".

### **Important Note on the Export Process**
The plugin uses a two-step process to convert a sequence:
1.  Premiere Pro first exports a high-quality "master" file to a temporary location.
2.  Our tool then converts this master file to H.265.

Currently, the first step uses a **simulated export** for development and compatibility purposes. This part of the code is clearly marked in `premiere_pro_plugin/host/premiere.jsx`. For a fully functional and reliable export, it is highly recommended to create a custom Adobe Media Encoder preset (`.epr` file) for a high-quality format like Apple ProRes and modify the script to use that preset file. This will ensure consistent, high-quality master files for conversion.
