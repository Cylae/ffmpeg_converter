/*
    premiere.jsx
    This script runs in the Premiere Pro host environment.
    It contains functions that the plugin panel's JavaScript can call.
*/

/**
 * Gets the name of the currently active sequence.
 * @returns {string} The name of the active sequence, or an empty string if none.
 */
function getActiveSequenceName() {
    if (app.project && app.project.activeSequence) {
        return app.project.activeSequence.name;
    }
    return ""; // Return empty string if no sequence is active
}

/**
 * Exports the active sequence to a high-quality temporary master file.
 * This uses a blocking call `exportAsMediaDirect` which is simpler than queuing
 * a job in Adobe Media Encoder.
 *
 * @returns {string} A JSON string with the result of the operation.
 *                   On success: { success: true, tempFilePath: "path/to/temp_file.mov", projectPath: "path/to/project.prproj" }
 *                   On failure: { success: false, message: "Error message" }
 */
function exportSequenceToTempFile() {
    if (!app.project || !app.project.activeSequence) {
        return JSON.stringify({
            success: false,
            message: "No active sequence found. Please select a sequence in the timeline."
        });
    }

    try {
        var sequence = app.project.activeSequence;
        var projectPath = app.project.path;

        // --- Define Paths ---
        var sequenceName = sequence.name.replace(/[\\/:"*?<>|]/g, '_'); // Sanitize name
        var tempFolder = new Folder(Folder.temp.fsName + "/h265_converter_temp");
        if (!tempFolder.exists) {
            tempFolder.create();
        }
        var tempOutputPath = tempFolder.fsName + "/" + sequenceName + "_master.mov";

        // The preset must be located inside the '/host' folder of the plugin.
        var extensionPath = $.fileName.split('/').slice(0, -1).join('/');
        var presetPath = extensionPath + "/master_preset.epr";
        var presetFile = new File(presetPath);

        // --- Preset Validation ---
        if (!presetFile.exists) {
            var errorMessage = "CRITICAL ERROR: The encoding preset 'master_preset.epr' was not found. " +
                               "Please create a high-quality 'Apple ProRes' or 'GoPro CineForm' preset in Adobe Media Encoder, " +
                               "name it 'master_preset.epr', and place it inside the plugin's '/host' directory.";
            return JSON.stringify({ success: false, message: errorMessage });
        }

        // --- Real Export ---
        // This is a synchronous/blocking call. The script will pause here until the export is complete.
        sequence.exportAsMediaDirect(
            tempOutputPath,
            presetPath,
            app.encoder.ENCODE_ENTIRE
        );

        // Check if the output file was actually created
        var outputFile = new File(tempOutputPath);
        if (!outputFile.exists) {
            throw new Error("The export completed, but the master file was not found at the expected path.");
        }

        return JSON.stringify({
            success: true,
            tempFilePath: tempOutputPath,
            projectPath: projectPath, // Pass project path for final output location
            message: "Master file exported successfully. Starting conversion."
        });

    } catch (e) {
        return JSON.stringify({
            success: false,
            message: "An unexpected error occurred during export: " + e.toString()
        });
    }
}
