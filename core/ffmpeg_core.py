import subprocess
import os
import re
import shlex
import json
import sys

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
            return subprocess.run(command, capture_output=True, text=True, check=True, encoding='utf-8')
        except FileNotFoundError:
            raise FFmpegError(f"Executable not found: {command[0]}. Please ensure ffmpeg/ffprobe is installed and in your PATH.")
        except subprocess.CalledProcessError as e:
            raise FFmpegError(f"Command failed with exit code {e.returncode}:\n{e.stderr}")

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
        """Gets the duration of a video file in seconds."""
        command = [
            self.ffprobe_path, '-v', 'error', '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1', input_path
        ]
        result = self._run_command(command)
        try:
            return float(result.stdout.strip())
        except ValueError:
            raise FFmpegError(f"Could not parse video duration from ffprobe output: {result.stdout}")

    def _build_command(self, input_path, output_path, video_codec, quality_mode, quality_value, audio_codec, hw_accel):
        """Builds the FFmpeg command as a list of arguments."""
        command = [self.ffmpeg_path]

        # Hardware Acceleration
        if hw_accel and hw_accel != 'none':
            command.extend(['-hwaccel', hw_accel])

        # Input
        command.extend(['-i', input_path])

        # Video Codec
        command.extend(['-c:v', video_codec])

        # Video Quality/Bitrate
        if quality_mode == 'crf':
            command.extend(['-crf', str(quality_value)])
        elif quality_mode == 'cbr':
            bitrate = str(quality_value) + 'M'
            command.extend(['-b:v', bitrate, '-minrate', bitrate, '-maxrate', bitrate, '-bufsize', '2M'])
        elif quality_mode == 'cq': # For NVENC
             command.extend(['-rc', 'vbr', '-cq', str(quality_value), '-qmin', str(quality_value), '-qmax', str(quality_value)])


        # Audio Codec
        command.extend(['-c:a', audio_codec])
        if audio_codec != 'copy':
            command.extend(['-b:a', '192k']) # Sensible default for audio bitrate

        # Overwrite output and final path
        command.extend(['-y', output_path])

        return command


    def convert(self, input_path, output_path,
                video_codec='libx265',
                quality_mode='crf',
                quality_value=23,
                audio_codec='copy',
                hw_accel=None, # Not used in command yet, for future use
                progress_callback=None):
        """
        Converts a video file using FFmpeg.
        :param input_path: Path to the input video file.
        :param output_path: Path for the converted output file.
        :param video_codec: The video encoder to use (e.g., 'libx265', 'h264_nvenc').
        :param quality_mode: 'crf' (Constant Rate Factor) or 'cbr' (Constant Bitrate).
        :param quality_value: The CRF value (e.g., 23) or CBR value in Megabits (e.g., 10).
        :param audio_codec: The audio encoder to use (e.g., 'aac', 'copy').
        :param hw_accel: (Future use) Specify hardware acceleration.
        :param progress_callback: A function to call with progress updates (percentage, message).
        """
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        duration = 0
        try:
            duration = self.get_video_duration(input_path)
        except FFmpegError as e:
            if progress_callback:
                progress_callback(-1, f"Warning: Could not get video duration. Progress will not be shown. Error: {e}")

        command = self._build_command(
            input_path, output_path, video_codec, quality_mode, quality_value, audio_codec, hw_accel
        )

        time_regex = re.compile(r"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})")

        process = subprocess.Popen(command, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, universal_newlines=True, encoding='utf-8')

        for line in process.stderr:
            if progress_callback:
                match = time_regex.search(line)
                if match:
                    h, m, s, _ = map(int, match.groups())
                    total_seconds = h * 3600 + m * 60 + s
                    if duration > 0:
                        percentage = min(100, int((total_seconds / duration) * 100))
                        progress_callback(percentage, line.strip())
                else:
                    progress_callback(-1, line.strip())

        process.wait()

        if process.returncode != 0:
            # The stderr pipe is consumed, so we can't get the full error here.
            # The Popen call would need to be redesigned to store stderr if we want the full error message.
            raise FFmpegError(f"FFmpeg failed with return code {process.returncode}. Check console for details.")

        if progress_callback:
            progress_callback(100, "Conversion complete!")

        return True

# Simple CLI for testing the new features
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="FFmpeg Core Converter Test CLI")
    parser.add_argument('--action', choices=['list_encoders', 'convert'], required=True)
    # Conversion arguments
    parser.add_argument('--input', help="Input video file")
    parser.add_argument('--output', help="Output video file")
    parser.add_argument('--vcodec', default='libx265', help="Video codec")
    parser.add_argument('--qmode', default='crf', choices=['crf', 'cbr', 'cq'], help="Quality mode")
    parser.add_argument('--qvalue', type=int, default=23, help="Quality value (CRF or CBR in Mb)")
    parser.add_argument('--acodec', default='copy', help="Audio codec")

    args = parser.parse_args()

    converter = FFmpegConverter()

    if args.action == 'list_encoders':
        try:
            print("Available Encoders:")
            print(json.dumps(converter.get_available_encoders(), indent=2))
        except FFmpegError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)

    elif args.action == 'convert':
        if not all([args.input, args.output]):
            print("Error: --input and --output are required for conversion.", file=sys.stderr)
            sys.exit(1)

        def cli_progress(percent, msg):
            if percent >= 0:
                print(f"PROGRESS: {percent}%")
            else:
                # print(f"LOG: {msg}") # This can be very verbose
                pass

        try:
            print(f"Starting conversion...")
            converter.convert(
                args.input,
                args.output,
                video_codec=args.vcodec,
                quality_mode=args.qmode,
                quality_value=args.qvalue,
                audio_codec=args.acodec,
                progress_callback=cli_progress
            )
            print("Conversion finished successfully!")
        except (FFmpegError, FileNotFoundError) as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
