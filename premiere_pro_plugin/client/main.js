window.onload = function () {
    'use strict';

    // Check if running in a CEP environment
    if (typeof CSInterface === 'undefined') {
        console.log("Not in a CEP environment. Exiting.");
        // You could show a message to the user here
        document.body.innerHTML = "<h1>Error: This panel must be run inside Adobe Premiere Pro.</h1>";
        return;
    }

    var csInterface = new CSInterface();
    var nodeProcess = require('child_process');
    var path = require('path');
    var fs = require('fs');

    // UI Elements
    var sequenceNameElem = document.getElementById('sequence-name');
    var startBtn = document.getElementById('start-btn');
    var progressBar = document.getElementById('progress-bar');
    var statusLabel = document.getElementById('status-label');
    var modeRadios = document.getElementsByName('mode');
    var crfValueInput = document.getElementById('crf-value');
    var cbrValueInput = document.getElementById('cbr-value');

    function init() {
        // Get active sequence name on load
        csInterface.evalScript('getActiveSequenceName()', function (result) {
            if (result) {
                sequenceNameElem.textContent = result;
            } else {
                sequenceNameElem.textContent = "No active sequence found.";
                sequenceNameElem.style.color = "#ff9a9a";
                startBtn.disabled = true;
            }
        });

        startBtn.addEventListener('click', startExportProcess);

        // Add listeners to radio buttons to toggle disabled state of inputs
        modeRadios.forEach(function(radio) {
            radio.addEventListener('change', updateInputStates);
        });
        updateInputStates(); // Initial call
    }

    function updateInputStates() {
        var isCrf = getSelectedMode() === 'crf';
        crfValueInput.disabled = !isCrf;
        cbrValueInput.disabled = isCrf;
    }

    function startExportProcess() {
        toggleUI(false);
        statusLabel.textContent = "Step 1/2: Preparing master file export from Premiere Pro...";
        progressBar.value = 0;

        csInterface.evalScript('exportSequenceToTempFile()', function (result) {
            try {
                var res = JSON.parse(result);
                if (res.success) {
                    statusLabel.textContent = "Step 2/2: Converting master file to H.265...";
                    // The JSX script now blocks until the export is complete, so we can run the conversion immediately.
                    // No more simulation, fake delays, or fake files.
                    runFfmpegConversion(res.tempFilePath, res.projectPath);
                } else {
                    // Display the detailed error message from the JSX script
                    statusLabel.textContent = "Error: " + res.message;
                    toggleUI(true);
                }
            } catch (e) {
                statusLabel.textContent = "Error parsing response from Premiere: " + e;
                toggleUI(true);
            }
        });
    }

    function runFfmpegConversion(tempMasterPath, projectPath) {
        var mode = getSelectedMode();
        var value = mode === 'crf' ? crfValueInput.value : cbrValueInput.value;

        var baseDir = csInterface.getSystemPath(SystemPath.EXTENSION);
        var pythonScriptPath = path.resolve(baseDir, '..', 'core', 'ffmpeg_core.py');
        var finalOutputPath = getFinalOutputPath(tempMasterPath, projectPath);

        var args = [
            pythonScriptPath,
            tempMasterPath,
            finalOutputPath,
            '--mode', mode,
            '--value', value
        ];

        var process = nodeProcess.spawn('python3', args);

        process.stdout.on('data', function (data) {
            var lines = data.toString().split('\n');
            lines.forEach(function(line) {
                if (line) {
                    try {
                        var update = JSON.parse(line);
                        if (update.type === 'progress') {
                            if (update.percentage > -1) {
                                progressBar.value = update.percentage;
                            }
                            if (update.message.includes('frame=') || update.message.includes('bitrate=')) {
                                statusLabel.textContent = `Converting: ${update.message}`;
                            }
                        } else if (update.type === 'error') {
                             statusLabel.textContent = `ERROR: ${update.message}`;
                        }
                    } catch (e) {
                        console.error("Failed to parse JSON from python script: ", line);
                    }
                }
            });
        });

        var stderrOutput = ''; // Variable to accumulate stderr
        process.stderr.on('data', function (data) {
            console.error(`stderr: ${data}`);
            stderrOutput += data.toString();
        });

        process.on('close', function (code) {
            if (code === 0) {
                progressBar.value = 100;
                statusLabel.textContent = 'Conversion complete! Final file saved.';
                // Clean up the temporary master file
                try {
                    fs.unlinkSync(tempMasterPath);
                } catch (e) {
                    console.error("Could not delete temp file: " + e);
                }
            } else {
                 // Check if a specific JSON error was already displayed
                 if (!statusLabel.textContent.startsWith('ERROR')) {
                    var finalErrorMessage = 'ERROR: Conversion script failed.';
                    if (stderrOutput) {
                        // Prioritize showing stderr if it contains anything
                        finalErrorMessage = 'ERROR: ' + stderrOutput.trim();
                    }
                    statusLabel.textContent = finalErrorMessage;
                 }
            }
            toggleUI(true);
        });
    }

    function toggleUI(enabled) {
        startBtn.disabled = !enabled;
        modeRadios.forEach(r => r.disabled = !enabled);
        updateInputStates(); // This will handle the text inputs
    }

    function getSelectedMode() {
        return document.querySelector('input[name="mode"]:checked').value;
    }

    function getFinalOutputPath(tempPath, projectPath) {
        // If the project is unsaved, projectPath will be undefined.
        // In that case, save next to the temp file as a fallback.
        var projectDir = projectPath ? path.dirname(projectPath) : path.dirname(tempPath);
        var sequenceName = path.basename(tempPath, '_master.mov');
        return path.join(projectDir, sequenceName + '_h265.mp4');
    }

    init();
};
