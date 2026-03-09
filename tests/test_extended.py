import pytest
import os
import shutil
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from core.ffmpeg_core import FFmpegConverter, FFmpegError

TEST_VIDEOS_DIR = os.path.join(os.path.dirname(__file__), '..', 'test_videos')
TEST_OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'test_output_extended')

VIDEOS = {
    'sample': os.path.join(TEST_VIDEOS_DIR, 'sample.mp4'),
    'short': os.path.join(TEST_VIDEOS_DIR, 'short_video.mp4'),
    'no_audio': os.path.join(TEST_VIDEOS_DIR, 'no_audio.mp4'),
    'audio_only': os.path.join(TEST_VIDEOS_DIR, 'audio_only.m4a'),
    'corrupted': os.path.join(TEST_VIDEOS_DIR, 'corrupted.mp4'),
    'special_chars': os.path.join(TEST_VIDEOS_DIR, 'special characters !@#$%^&*() _+.mp4'),
    'not_exists': os.path.join(TEST_VIDEOS_DIR, 'non_existent_file.mp4'),
}

@pytest.fixture(scope="module")
def converter():
    return FFmpegConverter()

@pytest.fixture(scope="function")
def output_dir():
    if os.path.exists(TEST_OUTPUT_DIR):
        shutil.rmtree(TEST_OUTPUT_DIR)
    os.makedirs(TEST_OUTPUT_DIR)
    yield TEST_OUTPUT_DIR
    shutil.rmtree(TEST_OUTPUT_DIR)

class TestGiganticSuite:

    @pytest.mark.parametrize("video_key", ['sample', 'short', 'no_audio', 'special_chars'])
    @pytest.mark.parametrize("vcodec", ['libx264', 'libx265'])
    @pytest.mark.parametrize("quality_mode", ['crf', 'cq'])
    def test_valid_conversions(self, converter, output_dir, video_key, vcodec, quality_mode):
        input_file = VIDEOS[video_key]
        if not os.path.exists(input_file):
            pytest.skip(f"Test file missing: {input_file}")

        out_name = f"out_{video_key}_{vcodec}_{quality_mode}.mp4"
        output_file = os.path.join(output_dir, out_name)

        result = converter.convert(input_file, output_file, video_codec=vcodec, quality_mode=quality_mode, quality_value=28)
        assert result is True
        assert os.path.exists(output_file)
        assert os.path.getsize(output_file) > 0

    @pytest.mark.parametrize("video_key", ['audio_only'])
    def test_audio_only_duration(self, converter, video_key):
        input_file = VIDEOS[video_key]
        if not os.path.exists(input_file):
            pytest.skip(f"Test file missing: {input_file}")

        # Audio only might have N/A for video streams or duration depending on ffprobe flags
        # In our case we generated m4a, let's see how duration handles it.
        # We expect it to not throw ValueError 'N/A'
        try:
            dur = converter.get_video_duration(input_file)
            assert isinstance(dur, float)
            assert dur > 0
        except FFmpegError as e:
            pass # if it can't parse duration, FFmpegError is expected, ValueError is not.

    def test_get_video_duration_na(self, converter, monkeypatch):
        # We can mock _run_command to return "N/A" to ensure the logic works.
        class MockResult:
            def __init__(self, stdout):
                self.stdout = stdout

        def mock_run_command(self, cmd):
            return MockResult("N/A\n")

        monkeypatch.setattr(converter, '_run_command', mock_run_command.__get__(converter, FFmpegConverter))

        # Test it directly
        dur = converter.get_video_duration('dummy.mp4')
        assert dur == 0.0

    def test_get_video_duration_empty(self, converter, monkeypatch):
        class MockResult:
            def __init__(self, stdout):
                self.stdout = stdout

        def mock_run_command(self, cmd):
            return MockResult("\n")

        monkeypatch.setattr(converter, '_run_command', mock_run_command.__get__(converter, FFmpegConverter))

        dur = converter.get_video_duration('dummy.mp4')
        assert dur == 0.0

    def test_get_video_duration_corrupted(self, converter):
        input_file = VIDEOS['corrupted']
        if not os.path.exists(input_file):
            pytest.skip("Test file missing")

        with pytest.raises(FFmpegError):
            converter.get_video_duration(input_file)

    def test_convert_corrupted(self, converter, output_dir):
        input_file = VIDEOS['corrupted']
        output_file = os.path.join(output_dir, 'out_corrupted.mp4')
        with pytest.raises(FFmpegError):
            converter.convert(input_file, output_file)

    def test_convert_not_exists(self, converter, output_dir):
        input_file = VIDEOS['not_exists']
        output_file = os.path.join(output_dir, 'out_not_exists.mp4')
        with pytest.raises(FileNotFoundError):
            converter.convert(input_file, output_file)

    def test_convert_invalid_codec(self, converter, output_dir):
        input_file = VIDEOS['sample']
        output_file = os.path.join(output_dir, 'out_invalid_codec.mp4')
        with pytest.raises(FFmpegError):
            converter.convert(input_file, output_file, video_codec='invalid_codec_xyz')

    def test_convert_audio_only(self, converter, output_dir):
        input_file = VIDEOS['audio_only']
        output_file = os.path.join(output_dir, 'out_audio_only.m4a')

        # Audio only might fail with default mp4 video options because there's no video stream
        try:
             converter.convert(input_file, output_file)
        except FFmpegError:
             pass # FFmpegError is acceptable if it complains about missing video stream and we requested video codecs
