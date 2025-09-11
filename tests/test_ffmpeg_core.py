import pytest
import os
import subprocess
import shutil
import json
from unittest.mock import patch, Mock

# Adjust the path to import from the parent directory
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from core.ffmpeg_core import FFmpegConverter, FFmpegError

# --- Constants ---
# The integration tests are skipped if this file doesn't exist.
SAMPLE_VIDEO = os.path.join(os.path.dirname(__file__), '..', 'test_videos', 'sample.mp4')
TEST_OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'test_output')


# --- Fixtures ---
@pytest.fixture(scope="module")
def converter():
    """Provides a default FFmpegConverter instance for tests."""
    return FFmpegConverter()

@pytest.fixture(scope="function")
def output_dir():
    """Creates and cleans up a directory for test outputs."""
    if os.path.exists(TEST_OUTPUT_DIR):
        shutil.rmtree(TEST_OUTPUT_DIR)
    os.makedirs(TEST_OUTPUT_DIR)
    yield TEST_OUTPUT_DIR
    shutil.rmtree(TEST_OUTPUT_DIR)

# --- Mocks ---
MOCK_ENCODERS_OUTPUT = """
Encoders:
 V..... libx264
 V..... libx265
 V.S... h264_nvenc
 V.S... hevc_nvenc
 A..... aac
"""

# --- Unit Tests (No actual ffmpeg calls) ---

def test_build_command_crf(converter):
    """Test CRF command building."""
    cmd = converter._build_command('in.mp4', 'out.mp4', 'libx265', 'crf', 23, 'copy', None)
    expected = ['ffmpeg', '-y', '-i', 'in.mp4', '-c:v', 'libx265', '-preset', 'medium', '-crf', '23', '-c:a', 'copy', '-v', 'quiet', '-stats', '-progress', 'pipe:1', 'out.mp4']
    assert cmd == expected

def test_build_command_nvenc_cq(converter):
    """Test NVENC CQ command building."""
    cmd = converter._build_command('in.mp4', 'out.mp4', 'hevc_nvenc', 'cq', 24, 'copy', 'nvenc')
    assert '-hwaccel' in cmd
    assert 'cuda' in cmd
    assert '-c:v' in cmd
    assert 'hevc_nvenc' in cmd
    assert '-cq' in cmd
    assert '24' in cmd

def test_create_thumbnail_command(converter):
    """Test that create_thumbnail builds the correct command."""
    with patch.object(converter, '_run_command') as mock_run, \
         patch('os.path.exists', return_value=True): # Mock os.path.exists
        converter.create_thumbnail('in.mp4', 'out.jpg', timestamp='00:01:30')
        mock_run.assert_called_once()
        called_cmd = mock_run.call_args[0][0]
        expected_cmd = ['ffmpeg', '-ss', '00:01:30', '-i', 'in.mp4', '-vframes', '1', '-q:v', '2', '-y', 'out.jpg']
        assert called_cmd == expected_cmd

def test_create_gif_commands(converter):
    """Test that create_gif builds both palette and gif commands correctly."""
    with patch.object(converter, '_run_command') as mock_run, \
         patch('tempfile.NamedTemporaryFile') as mock_temp, \
         patch('os.remove'), \
         patch('os.path.exists', return_value=True): # Mock os.path.exists

        mock_temp.return_value.__enter__.return_value.name = '/tmp/palette.png'

        converter.create_gif('in.mp4', 'out.gif', '00:00:10', 5, fps=20, width=500)

        assert mock_run.call_count == 2

        palette_call_args = mock_run.call_args_list[0][0][0]
        expected_palette_cmd = [
            'ffmpeg', '-y', '-ss', '00:00:10', '-t', '5', '-i', 'in.mp4',
            '-vf', 'fps=20,scale=500:-1:flags=lanczos,palettegen', '/tmp/palette.png'
        ]
        assert palette_call_args == expected_palette_cmd

        gif_call_args = mock_run.call_args_list[1][0][0]
        expected_gif_cmd = [
            'ffmpeg', '-y', '-ss', '00:00:10', '-t', '5', '-i', 'in.mp4', '-i', '/tmp/palette.png',
            '-filter_complex', 'fps=20,scale=500:-1:flags=lanczos[x];[x][1:v]paletteuse', 'out.gif'
        ]
        assert gif_call_args == expected_gif_cmd

def test_get_available_encoders_mocked(converter):
    """Test parsing of available encoders from mocked ffmpeg output."""
    with patch.object(converter, '_run_command') as mock_run:
        mock_run.return_value = Mock(stdout=MOCK_ENCODERS_OUTPUT, returncode=0)
        encoders = converter.get_available_encoders(force_rescan=True)
        assert 'libx264' in encoders
        assert 'hevc_nvenc' in encoders
        assert 'aac' not in encoders

def test_convert_file_not_found(converter):
    """Test conversion raises FileNotFoundError for non-existent input."""
    with pytest.raises(FileNotFoundError):
        converter.convert('nonexistent.mp4', 'out.mp4')

def test_ffmpeg_error_on_failed_conversion(converter):
    """Test conversion raises FFmpegError if ffmpeg returns non-zero."""
    with patch('subprocess.Popen') as mock_popen, \
         patch('os.path.exists', return_value=True), \
         patch.object(converter, 'get_video_duration', return_value=10):

        mock_process = Mock()
        mock_process.communicate.return_value = ('', 'ffmpeg error message')
        mock_process.returncode = 1
        mock_process.stdout = []
        mock_popen.return_value = mock_process

        with pytest.raises(FFmpegError):
            converter.convert('anyfile.mp4', 'out.mp4')


# --- Integration Tests (Requires ffmpeg and a sample video) ---
@pytest.mark.skipif(not os.path.exists(SAMPLE_VIDEO), reason=f"Sample video not found at {SAMPLE_VIDEO}")
class TestIntegration:
    def _probe_file(self, filepath, converter):
        """Helper to run ffprobe on a file and get its format and stream info."""
        result = converter._run_command([
            converter.ffprobe_path, '-v', 'quiet', '-print_format', 'json',
            '-show_format', '-show_streams', filepath
        ])
        return json.loads(result.stdout)

    def test_integration_convert_h265_crf(self, converter, output_dir):
        """A real conversion to H.265 with CRF."""
        output_file = os.path.join(output_dir, 'output_h265_crf.mp4')
        result = converter.convert(SAMPLE_VIDEO, output_file, video_codec='libx265', quality_mode='crf', quality_value=28)
        assert result is True
        assert os.path.exists(output_file)
        info = self._probe_file(output_file, converter)
        assert info['streams'][0]['codec_name'] == 'hevc'

    def test_integration_convert_with_spaces_in_path(self, converter, output_dir):
        """A real conversion using a path with spaces."""
        spaced_input = os.path.join(output_dir, 'my test video.mp4')
        shutil.copy(SAMPLE_VIDEO, spaced_input)

        output_file = os.path.join(output_dir, 'output with spaces.mp4')
        result = converter.convert(spaced_input, output_file, video_codec='libx264', quality_mode='crf', quality_value=28)
        assert result is True
        assert os.path.exists(output_file)
        info = self._probe_file(output_file, converter)
        assert info['streams'][0]['codec_name'] == 'h264'

    def test_integration_create_thumbnail(self, converter, output_dir):
        """A real thumbnail creation."""
        output_file = os.path.join(output_dir, 'thumb.jpg')
        result = converter.create_thumbnail(SAMPLE_VIDEO, output_file, timestamp='00:00:00.5')
        assert result is True
        assert os.path.exists(output_file)
        assert os.path.getsize(output_file) > 1000

    def test_integration_create_gif(self, converter, output_dir):
        """A real animated GIF creation."""
        output_file = os.path.join(output_dir, 'anim.gif')
        result = converter.create_gif(SAMPLE_VIDEO, output_file, start_time='00:00:00', duration=1.0, fps=10, width=150)
        assert result is True
        assert os.path.exists(output_file)
        assert os.path.getsize(output_file) > 1000
