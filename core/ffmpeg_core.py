import subprocess
import os
import re
import shlex

class FFmpegError(Exception):
    """Custom exception for FFmpeg errors."""
    pass

class FFmpegConverter:
    def __init__(self, ffmpeg_path='ffmpeg'):
        """
        Initializes the converter.
        :param ffmpeg_path: Path to the FFmpeg executable. Defaults to 'ffmpeg'.
        """
        self.ffmpeg_path = ffmpeg_path

    def _get_video_duration(self, input_path):
        """
        Gets the duration of a video file in seconds.
        Uses ffprobe, which is expected to be in the same directory as ffmpeg.
        """
        ffprobe_path = self.ffmpeg_path.replace('ffmpeg', 'ffprobe')
        command = [
            ffprobe_path,
            '-v', 'error',
            '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1',
            input_path
        ]
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            return float(result.stdout.strip())
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            raise FFmpegError(f"Failed to get video duration with ffprobe: {e}")
        except ValueError:
            raise FFmpegError("Could not parse video duration.")

    def convert(self, input_path, output_path, options, progress_callback=None):
        """
        Converts a video file using FFmpeg.
        :param input_path: Path to the input video file.
        :param output_path: Path for the converted output file.
        :param options: A dictionary of encoding options.
                        e.g., {'mode': 'crf', 'value': 23} or {'mode': 'cbr', 'value': '10M'}
        :param progress_callback: A function to call with progress updates (percentage, message).
        """
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        try:
            duration = self._get_video_duration(input_path)
        except FFmpegError as e:
            duration = 0
            if progress_callback:
                progress_callback(-1, f"Warning: Could not get video duration. Progress will not be shown. Error: {e}")

        command = [self.ffmpeg_path, '-i', input_path]

        if options.get('mode') == 'crf':
            command.extend(['-c:v', 'libx265', '-crf', str(options.get('value', 23))])
        elif options.get('mode') == 'cbr':
            bitrate = str(options.get('value', '10')) + 'M'
            command.extend(['-c:v', 'libx265', '-b:v', bitrate, '-minrate', bitrate, '-maxrate', bitrate, '-bufsize', '2M'])
        else:
            raise ValueError("Invalid mode specified. Must be 'crf' or 'cbr'.")

        command.extend(['-c:a', 'copy'])
        command.extend(['-y', output_path])

        time_regex = re.compile(r"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})")

        process = subprocess.Popen(command, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, universal_newlines=True, encoding='utf-8')

        for line in process.stderr:
            if progress_callback:
                match = time_regex.search(line)
                if match:
                    hours = int(match.group(1))
                    minutes = int(match.group(2))
                    seconds = int(match.group(3))
                    total_seconds = hours * 3600 + minutes * 60 + seconds
                    if duration > 0:
                        percentage = min(100, int((total_seconds / duration) * 100))
                        progress_callback(percentage, line.strip())
                else:
                    progress_callback(-1, line.strip())

        process.wait()

        if process.returncode != 0:
            # Read the rest of the stderr to get the error message
            error_output = "".join(process.stderr.readlines())
            raise FFmpegError(f"FFmpeg failed with return code {process.returncode}. Error: {error_output}")

        if progress_callback:
            progress_callback(100, "Conversion complete!")

        return True


if __name__ == '__main__':
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(description="Convert a video file to H.265 using FFmpeg.")
    parser.add_argument("input_path", help="Path to the input video file.")
    parser.add_argument("output_path", help="Path for the converted output file.")
    parser.add_argument("--mode", required=True, choices=['crf', 'cbr'], help="Encoding mode: 'crf' or 'cbr'.")
    parser.add_argument("--value", required=True, type=int, help="CRF or Bitrate value.")

    args = parser.parse_args()

    def cli_progress_callback(percentage, message):
        """Prints progress updates as JSON, to be read by another process."""
        progress_data = {
            'type': 'progress',
            'percentage': percentage,
            'message': message
        }
        print(json.dumps(progress_data), flush=True)

    try:
        # We need to find the ffmpeg executable.
        # Let's assume it's in the system PATH.
        converter = FFmpegConverter()
        options = {'mode': args.mode, 'value': args.value}
        converter.convert(args.input_path, args.output_path, options, cli_progress_callback)
    except (FFmpegError, FileNotFoundError, ValueError) as e:
        error_data = {'type': 'error', 'message': str(e)}
        print(json.dumps(error_data), flush=True)
        sys.exit(1)
