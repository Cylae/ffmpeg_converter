import subprocess
import os
import re
import shlex
import json
import sys
import argparse

class FFmpegError(Exception):
    """Custom exception for FFmpeg errors."""
    pass

class FFmpegConverter:
    def __init__(self, ffmpeg_path='ffmpeg', ffprobe_path='ffprobe'):
        """
        Initializes the converter.
        :param ffmpeg_path: Path to the FFmpeg executable.
        :param ffprobe_path: Path to the FFprobe executable.
        """
        self.ffmpeg_path = ffmpeg_path
        self.ffprobe_path = ffprobe_path
        self._available_encoders = None

    def _run_command(self, command):
        """Helper to run a command and return its output."""
        try:
            # Set startupinfo for Windows to hide the console window
            startupinfo = None
            if sys.platform == "win32":
                startupinfo = subprocess.STARTUPINFO()
                startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startupinfo.wShowWindow = subprocess.SW_HIDE

            return subprocess.run(command, capture_output=True, text=True, check=True, encoding='utf-8', startupinfo=startupinfo)
        except FileNotFoundError:
            raise FFmpegError(f"Executable not found: {command[0]}. Please ensure ffmpeg/ffprobe is installed and in your PATH.")
        except subprocess.CalledProcessError as e:
            # The stderr contains the error message from ffmpeg
            raise FFmpegError(f"Command failed with exit code {e.returncode}:\n{e.stderr.strip()}")


    def get_available_encoders(self, force_rescan=False):
        """
        Gets a list of available video encoders from the ffmpeg executable.
        Caches the result for subsequent calls.
        """
        if self._available_encoders is not None and not force_rescan:
            return self._available_encoders

        result = self._run_command([self.ffmpeg_path, '-encoders'])
        encoders = []
        for line in result.stdout.splitlines():
            match = re.search(r'^\s*V\S*\s*(\S+)', line) # V... = Video encoder
            if match:
                encoders.append(match.group(1))
        self._available_encoders = encoders
        return self._available_encoders

    def get_video_duration(self, input_path):
        """Gets the duration of a video file in seconds using ffprobe."""
        command = [
            self.ffprobe_path, '-v', 'error', '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1', input_path
        ]
        result = self._run_command(command)
        try:
            return float(result.stdout.strip())
        except (ValueError, TypeError):
            raise FFmpegError(f"Could not parse video duration from ffprobe output: '{result.stdout}'")


    def _build_command(self, input_path, output_path, video_codec, quality_mode, quality_value, audio_codec, hw_accel):
        """Builds the FFmpeg command as a list of arguments."""
        command = [self.ffmpeg_path]

        # --- Input ---
        command.extend(['-i', input_path])

        is_hw_encode = 'nvenc' in video_codec or 'qsv' in video_codec or 'videotoolbox' in video_codec

        # --- Video Codec ---
        command.extend(['-c:v', video_codec])

        # Add pixel format for hardware encoders to ensure compatibility
        if is_hw_encode:
            command.extend(['-pix_fmt', 'yuv420p'])

        # --- Video Quality/Bitrate ---
        if quality_mode == 'crf':
            # CRF is for software encoders
            command.extend(['-crf', str(quality_value)])
        elif quality_mode == 'cbr':
            bitrate = str(quality_value) + 'M'
            # For HW encoders, CBR might need a specific flag
            if is_hw_encode:
                 command.extend(['-rc', 'cbr', '-b:v', bitrate, '-minrate', bitrate, '-maxrate', bitrate, '-bufsize', '2M'])
            else:
                 command.extend(['-b:v', bitrate, '-minrate', bitrate, '-maxrate', bitrate, '-bufsize', '2M'])
        elif quality_mode == 'cq':
            # Constant Quality is used for hardware encoders
            command.extend(['-rc', 'vbr', '-cq', str(quality_value)])

        # --- Audio Codec ---
        command.extend(['-c:a', audio_codec])
        if audio_codec != 'copy':
            command.extend(['-b:a', '192k'])

        # Add progress reporting flags
        # -v quiet -stats: Shows only the final stats line on stderr.
        # -progress pipe:1: Writes detailed key=value progress to stdout.
        command.extend(['-v', 'quiet', '-stats'])
        command.extend(['-progress', 'pipe:1'])

        # Overwrite output and final path
        command.extend(['-y', output_path])

        return command


    def convert(self, input_path, output_path,
                video_codec='libx265',
                quality_mode='crf',
                quality_value=23,
                audio_codec='copy',
                hw_accel=None,
                progress_callback=None):
        """
        Converts a video file using FFmpeg.
        :param progress_callback: A function to call with progress updates (percentage, message).
        """
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        duration_s = 0
        try:
            # ffprobe gives duration in microseconds for some formats, so we get the full format info
            duration_s = self.get_video_duration(input_path)
        except FFmpegError as e:
            if progress_callback:
                progress_callback(-1, f"Warning: Could not get video duration. Progress percentage will not be available. Error: {e}")

        command = self._build_command(
            input_path, output_path, video_codec, quality_mode, quality_value, audio_codec, hw_accel
        )

        # Regex for parsing the final stats line from stderr
        stats_regex = re.compile(r"frame=\s*(\d+).*fps=\s*(\d+\.?\d*).*time=(\S+).*bitrate=\s*(\S+).*speed=\s*(\S+)")

        # Set startupinfo for Windows to hide the console window
        startupinfo = None
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = subprocess.SW_HIDE

        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            encoding='utf-8',
            startupinfo=startupinfo
        )

        progress_data = {}
        for line in process.stdout:
            # Parse key=value progress data from stdout
            parts = line.strip().split('=')
            if len(parts) == 2:
                progress_data[parts[0]] = parts[1]

            if 'out_time_ms' in progress_data and duration_s > 0:
                elapsed_ms = int(progress_data['out_time_ms'])
                percentage = min(100, int((elapsed_ms / (duration_s * 1_000_000))))
                # Create a human-readable message
                message = (f"frame={progress_data.get('frame', 'N/A')} | "
                           f"bitrate={progress_data.get('bitrate', 'N/A')} | "
                           f"speed={progress_data.get('speed', 'N/A')}")
                if progress_callback:
                    progress_callback(percentage, message)

        # Wait for the process to finish and capture the rest of the output
        _, stderr_output = process.communicate()

        if process.returncode != 0:
            # If the process failed, the error is in stderr
            raise FFmpegError(f"FFmpeg failed with return code {process.returncode}:\n{stderr_output.strip()}")

        if progress_callback:
            final_stats = "Conversion complete!"
            # Try to find the final stats line in the stderr output
            match = stats_regex.search(stderr_output)
            if match:
                final_stats = f"Done! Final stats: time={match.group(3)} bitrate={match.group(4)} speed={match.group(5)}"
            progress_callback(100, final_stats)

        return True


# This interface is used by the Premiere Pro plugin
if __name__ == '__main__':
    # Setup for flushing stdout, required for piping to Node.js
    sys.stdout.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(description="FFmpeg Core Converter Wrapper")
    parser.add_argument("input", help="Input video file")
    parser.add_argument("output", help="Output video file")
    parser.add_argument("--mode", required=True, choices=['crf', 'cbr'], help="Quality mode")
    parser.add_argument("--value", required=True, type=int, help="Quality value (CRF or CBR in Mb)")
    # Optional arguments for future expansion
    parser.add_argument("--vcodec", default='libx265', help="Video codec")
    parser.add_argument("--acodec", default='copy', help="Audio codec")

    args = parser.parse_args()

    # --- JSON Progress Callback ---
    def json_progress_callback(percentage, message):
        """Formats progress into a JSON string and prints it."""
        progress = {
            "type": "progress",
            "percentage": percentage,
            "message": message
        }
        print(json.dumps(progress))

    # --- Main Execution ---
    converter = FFmpegConverter()
    try:
        converter.convert(
            args.input,
            args.output,
            video_codec=args.vcodec,
            quality_mode=args.mode,
            quality_value=args.value,
            audio_codec=args.acodec,
            progress_callback=json_progress_callback
        )
    except (FFmpegError, FileNotFoundError) as e:
        error_json = {
            "type": "error",
            "message": str(e)
        }
        print(json.dumps(error_json))
        sys.exit(1)
    except Exception as e:
        # Catch any other unexpected errors
        error_json = {
            "type": "error",
            "message": f"An unexpected error occurred: {e}"
        }
        print(json.dumps(error_json))
        sys.exit(1)
