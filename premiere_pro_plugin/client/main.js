window.onload = function () {
    'use strict';

    // Check if running in a CEP environment
    if (typeof CSInterface === 'undefined') {
        console.log("Not in a CEP environment. Exiting.");
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
        modeRadios.forEach(function(radio) {
            radio.addEventListener('change', updateInputStates);
        });
        updateInputStates();
    }

    function updateInputStates() {
        var isCrf = getSelectedMode() === 'crf';
        crfValueInput.disabled = !isCrf;
        cbrValueInput.disabled = isCrf;
    }

    function startExportProcess() {
        toggleUI(false);
        statusLabel.textContent = "Step 1/2: Exporting master file from Premiere Pro...";
        progressBar.value = 0;

        csInterface.evalScript('exportSequenceToTempFile()', function (result) {
            try {
                var res = JSON.parse(result);
                if (res.success) {
                    statusLabel.textContent = "Step 2/2: Converting master file to H.265...";
                    runFfmpegConversion(res.tempFilePath, res.projectPath);
                } else {
                    statusLabel.textContent = "Export Error: " + res.message;
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

        // --- Updated Arguments for the new core script ---
        var args = [
            pythonScriptPath,
            'convert',
            tempMasterPath,
            finalOutputPath,
            '--vcodec', 'libx265', // The panel is for H.265, so this is fixed.
            '--acodec', 'copy',    // 'copy' is a safe and fast default.
            '--mode', mode,
            '--value', value
            // hwaccel is not exposed in this simple UI
        ];

        var process = nodeProcess.spawn('python3', args);
        var lastMessage = '';

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
                            statusLabel.textContent = `Converting: ${update.message}`;
                            lastMessage = update.message; // Store last good message
                        } else if (update.type === 'error' || update.type === 'unexpected_error') {
                             statusLabel.textContent = `ERROR: ${update.message}`;
                        } else if (update.type === 'success') {
                            statusLabel.textContent = update.message;
                        }
                    } catch (e) {
                        console.error("Failed to parse JSON from python script: ", line);
                        statusLabel.textContent = "An unknown error occurred while parsing script output.";
                    }
                }
            });
        });

        var stderrOutput = '';
        process.stderr.on('data', function (data) {
            // Stderr is now only for unexpected Python errors, not ffmpeg output
            console.error(`stderr: ${data}`);
            stderrOutput += data.toString();
        });

        process.on('close', function (code) {
            if (code === 0) {
                progressBar.value = 100;
                // The final success message should already be set from stdout JSON
                if (!statusLabel.textContent.toLowerCase().includes('complete')) {
                    statusLabel.textContent = 'Conversion complete! Final file saved.';
                }
                // Clean up the temporary master file
                try {
                    fs.unlinkSync(tempMasterPath);
                } catch (e) {
                    console.error("Could not delete temp file: " + e);
                }
            } else {
                 if (!statusLabel.textContent.startsWith('ERROR')) {
                    var finalErrorMessage = `ERROR: Conversion script exited with code ${code}.`;
                    if (stderrOutput) {
                        finalErrorMessage += ` Details: ${stderrOutput.trim()}`;
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
        crfValueInput.disabled = !enabled;
        cbrValueInput.disabled = !enabled;
        updateInputStates();
    }

    function getSelectedMode() {
        return document.querySelector('input[name="mode"]:checked').value;
    }

    function getFinalOutputPath(tempPath, projectPath) {
        var projectDir = projectPath ? path.dirname(projectPath) : path.dirname(tempPath);
        var sequenceName = path.basename(tempPath, '.mov');
        // Sanitize the sequence name in case it's the temp master file name
        sequenceName = sequenceName.replace('_master', '');
        return path.join(projectDir, sequenceName + '_h265.mp4');
    }

    init();
};
