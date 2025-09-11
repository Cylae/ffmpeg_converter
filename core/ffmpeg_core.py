import subprocess
import os
import re
import shlex
import json
import sys
import argparse
import tempfile

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

    def _run_command(self, command, capture_output=True):
        """
        Helper to run a command and handle common errors.
        If capture_output is False, stdout/stderr will be inherited.
        """
        try:
            # Set startupinfo for Windows to hide the console window
            startupinfo = None
            if sys.platform == "win32":
                startupinfo = subprocess.STARTUPINFO()
                startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startupinfo.wShowWindow = subprocess.SW_HIDE

            # Using a list of args with subprocess is safer than a single string
            return subprocess.run(
                command,
                capture_output=capture_output,
                text=True,
                check=True,
                encoding='utf-8',
                startupinfo=startupinfo
            )
        except FileNotFoundError:
            raise FFmpegError(f"Executable not found: {command[0]}. Please ensure ffmpeg/ffprobe is installed and in your PATH.")
        except subprocess.CalledProcessError as e:
            # The stderr contains the error message from ffmpeg
            error_output = e.stderr.strip() if e.stderr else "No stderr output."
            raise FFmpegError(f"Command failed with exit code {e.returncode}:\n{error_output}")


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

    def create_thumbnail(self, input_path, output_path, timestamp='00:00:10'):
        """Creates a single thumbnail from a video."""
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        command = [
            self.ffmpeg_path,
            '-ss', timestamp,
            '-i', input_path,
            '-vframes', '1',
            '-q:v', '2',  # High-quality JPEG
            '-y', output_path
        ]
        self._run_command(command, capture_output=True)
        return True

    def create_gif(self, input_path, output_path, start_time, duration, fps=15, width=480):
        """Creates an animated GIF from a video clip."""
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_palette:
            palette_path = temp_palette.name

        try:
            # Step 1: Generate the color palette for a high-quality GIF
            palette_vf = f"fps={fps},scale={width}:-1:flags=lanczos,palettegen"
            palette_command = [
                self.ffmpeg_path, '-y',
                '-ss', start_time,
                '-t', str(duration),
                '-i', input_path,
                '-vf', palette_vf,
                palette_path
            ]
            self._run_command(palette_command, capture_output=True)

            # Step 2: Create the GIF using the generated palette
            gif_filter_complex = f"fps={fps},scale={width}:-1:flags=lanczos[x];[x][1:v]paletteuse"
            gif_command = [
                self.ffmpeg_path, '-y',
                '-ss', start_time,
                '-t', str(duration),
                '-i', input_path,
                '-i', palette_path,
                '-filter_complex', gif_filter_complex,
                output_path
            ]
            self._run_command(gif_command, capture_output=True)

        finally:
            # Clean up the temporary palette file
            if os.path.exists(palette_path):
                os.remove(palette_path)

        return True


    def _build_command(self, input_path, output_path, video_codec, quality_mode, quality_value, audio_codec, hw_accel):
        """Builds the FFmpeg command as a list of arguments."""
        command = [self.ffmpeg_path, '-y']

        # --- Hardware Acceleration ---
        is_hw_encode = 'nvenc' in video_codec or 'qsv' in video_codec or 'videotoolbox' in video_codec
        if hw_accel and hw_accel != 'none':
            if hw_accel == 'nvenc':
                accel_method = 'cuda'
            else:
                accel_method = hw_accel
            command.extend(['-hwaccel', accel_method])
            if accel_method == 'cuda':
                command.extend(['-hwaccel_output_format', 'cuda'])

        # --- Input ---
        command.extend(['-i', input_path])

        # --- Video Codec ---
        command.extend(['-c:v', video_codec])
        if is_hw_encode:
            command.extend(['-pix_fmt', 'yuv420p']) # Common pixel format for compatibility
        else:
            # Use a good default preset for software encoding
            command.extend(['-preset', 'medium'])

        # --- Video Quality/Bitrate ---
        if quality_mode == 'crf':
            command.extend(['-crf', str(quality_value)])
        elif quality_mode == 'cbr':
            bitrate = str(quality_value) + 'M'
            command.extend(['-b:v', bitrate, '-minrate', bitrate, '-maxrate', bitrate, '-bufsize', '2M'])
        elif quality_mode == 'cq':
            command.extend(['-rc', 'vbr', '-cq', str(quality_value)])

        # --- Audio Codec ---
        command.extend(['-c:a', audio_codec])
        if audio_codec != 'copy':
            command.extend(['-b:a', '192k'])

        # --- Progress Reporting & Final Output ---
        command.extend(['-v', 'quiet', '-stats', '-progress', 'pipe:1', output_path])

        return command


    def convert(self, input_path, output_path,
                video_codec='libx265',
                quality_mode='crf',
                quality_value=23,
                audio_codec='copy',
                hw_accel=None,
                progress_callback=None):
        """
        Converts a video file using FFmpeg, providing progress updates.
        """
        if not os.path.exists(input_path):
            raise FileNotFoundError(f"Input file not found: {input_path}")

        duration_s = self.get_video_duration(input_path)

        command = self._build_command(
            input_path, output_path, video_codec, quality_mode, quality_value, audio_codec, hw_accel
        )

        stats_regex = re.compile(r"frame=\s*(\d+).*fps=\s*(\d+\.?\d*).*time=(\S+).*bitrate=\s*(\S+).*speed=\s*(\S+)")

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
            parts = line.strip().split('=')
            if len(parts) == 2:
                progress_data[parts[0]] = parts[1]

            if 'out_time_ms' in progress_data and duration_s > 0:
                elapsed_ms = int(progress_data['out_time_ms'])
                percentage = min(100, int((elapsed_ms / (duration_s * 1_000_000))))
                message = (f"frame={progress_data.get('frame', 'N/A')} | "
                           f"bitrate={progress_data.get('bitrate', 'N/A')} | "
                           f"speed={progress_data.get('speed', 'N/A')}")
                if progress_callback:
                    progress_callback(percentage, message)

        _, stderr_output = process.communicate()

        if process.returncode != 0:
            raise FFmpegError(f"FFmpeg failed with return code {process.returncode}:\n{stderr_output.strip()}")

        if progress_callback:
            final_stats = "Conversion complete!"
            match = stats_regex.search(stderr_output)
            if match:
                final_stats = f"Done! Final stats: time={match.group(3)} bitrate={match.group(4)} speed={match.group(5)}"
            progress_callback(100, final_stats)

        return True


# --- JSON Progress & Error Reporting ---
def json_progress_callback(percentage, message):
    """Formats progress into a JSON string and prints it."""
    print(json.dumps({"type": "progress", "percentage": percentage, "message": message}))

def print_json_error(e, error_type="error"):
    """Formats an error message into a JSON string and prints it."""
    print(json.dumps({"type": error_type, "message": str(e)}))
    sys.exit(1)


# --- Main Command-Line Interface ---
if __name__ == '__main__':
    # Setup for flushing stdout, required for piping to Node.js
    sys.stdout.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(
        description="FFmpeg Core Wrapper for video conversion, thumbnail, and GIF generation."
    )
    subparsers = parser.add_subparsers(dest='command', required=True, help='Available commands')

    # --- Convert Command ---
    parser_convert = subparsers.add_parser('convert', help='Convert a video file.')
    parser_convert.add_argument('input', help='Input video file path.')
    parser_convert.add_argument('output', help='Output video file path.')
    parser_convert.add_argument('--vcodec', default='libx265', help='Video codec (e.g., libx265, hevc_nvenc).')
    parser_convert.add_argument('--acodec', default='copy', help='Audio codec (e.g., copy, aac).')
    parser_convert.add_argument('--mode', required=True, choices=['crf', 'cbr', 'cq'], help='Quality mode.')
    parser_convert.add_argument('--value', required=True, type=int, help='Quality value (CRF, CBR in Mbps, or CQ).')
    parser_convert.add_argument('--hwaccel', default='none', help='Hardware acceleration method (e.g., nvenc, qsv).')

    # --- Thumbnail Command ---
    parser_thumb = subparsers.add_parser('thumbnail', help='Create a thumbnail from a video.')
    parser_thumb.add_argument('input', help='Input video file path.')
    parser_thumb.add_argument('output', help='Output thumbnail file path.')
    parser_thumb.add_argument('--timestamp', default='00:00:10', help='Timestamp for the thumbnail (HH:MM:SS).')

    # --- GIF Command ---
    parser_gif = subparsers.add_parser('gif', help='Create an animated GIF from a video.')
    parser_gif.add_argument('input', help='Input video file path.')
    parser_gif.add_argument('output', help='Output GIF file path.')
    parser_gif.add_argument('--start', required=True, help='Start time for the GIF (HH:MM:SS).')
    parser_gif.add_argument('--duration', required=True, type=float, help='Duration of the GIF in seconds.')
    parser_gif.add_argument('--fps', default=15, type=int, help='Frames per second for the GIF.')
    parser_gif.add_argument('--width', default=480, type=int, help='Width of the GIF in pixels.')

    args = parser.parse_args()
    converter = FFmpegConverter()

    try:
        if args.command == 'convert':
            converter.convert(
                args.input,
                args.output,
                video_codec=args.vcodec,
                quality_mode=args.mode,
                quality_value=args.value,
                audio_codec=args.acodec,
                hw_accel=args.hwaccel,
                progress_callback=json_progress_callback
            )
        elif args.command == 'thumbnail':
            converter.create_thumbnail(args.input, args.output, timestamp=args.timestamp)
            print(json.dumps({"type": "success", "message": f"Thumbnail saved to {args.output}"}))

        elif args.command == 'gif':
            converter.create_gif(
                args.input, args.output,
                start_time=args.start,
                duration=args.duration,
                fps=args.fps,
                width=args.width
            )
            print(json.dumps({"type": "success", "message": f"GIF saved to {args.output}"}))

    except (FFmpegError, FileNotFoundError) as e:
        print_json_error(e)
    except Exception as e:
        print_json_error(e, error_type="unexpected_error")
