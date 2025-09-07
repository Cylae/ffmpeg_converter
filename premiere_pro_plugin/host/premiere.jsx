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
 * "Exports" the active sequence to a temporary file.
 * NOTE: This is a placeholder/simulation. The actual app.encoder.encodeSequence()
 * call is commented out because finding a reliable, cross-platform preset path
 * is complex and requires a bundled .epr file, which we don't have yet.
 *
 * This function creates a temporary directory and returns a simulated file path.
 * This allows the rest of the plugin's workflow (JS -> Python) to be built and tested.
 *
 * @returns {string} A JSON string with the result of the operation.
 *                   On success: { success: true, tempFilePath: "path/to/temp_file.mov" }
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

        // Sanitize the sequence name to create a valid filename
        var sequenceName = sequence.name.replace(/[\\/:"*?<>|]/g, '_');

        // Create a temporary folder for the master file
        var tempFolder = new Folder(Folder.temp.fsName + "/h265_converter_temp");
        if (!tempFolder.exists) {
            tempFolder.create();
        }

        var tempOutputPath = tempFolder.fsName + "/" + sequenceName + "_master.mov";

        /*
        // --- THIS IS THE REAL EXPORT CODE THAT IS CURRENTLY STUBBED OUT ---
        // To make this work, we need a reliable path to a high-quality .epr preset file.
        // This file should be bundled with the plugin.
        var presetPath = "path/to/your/bundled/preset.epr";

        app.encoder.launchEncoder(); // Ensure Adobe Media Encoder is running

        var jobID = app.encoder.encodeSequence(
            sequence,
            tempOutputPath,
            presetPath,
            app.encoder.ENCODE_ENTIRE, // or ENCODE_WORKAREA
            1 // 1 = remove from queue when done, 0 = keep
        );

        // The real version would need to monitor the job progress.
        // For now, we just simulate success immediately.
        */

        // Simulate a successful export and return the path to the theoretical master file.
        return JSON.stringify({
            success: true,
            tempFilePath: tempOutputPath,
            message: "Premiere Pro is now exporting the master file. The conversion will begin shortly."
        });

    } catch (e) {
        return JSON.stringify({
            success: false,
            message: "An unexpected error occurred during export: " + e.toString()
        });
    }
}
