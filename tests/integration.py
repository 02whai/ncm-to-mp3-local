#!/usr/bin/env python3
"""Exercise the real ncmdump/FFmpeg pipeline using generated audio, never copyrighted songs."""
from pathlib import Path
import base64
import hashlib
import json
import os
import shutil
import struct
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "build/ncm2mp3"
APP = ROOT / "dist/NCM 转 MP3.app"
ENV = dict(os.environ, NCM2MP3_NCMDUMP=str(APP / "Contents/Resources/bin/ncmdump"))
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
FFPROBE = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"
CORE = bytes.fromhex("687a4852416d736f356b496e62617857")
META = bytes.fromhex("2331346c6a6b5f215c5d2630553c2728")
KEY_PREFIX = bytes.fromhex("6e657465617365636c6f75646d75736963")
METADATA_PREFIX = bytes.fromhex("313633206b657928446f6e2774206d6f64696679293a")


def command(*arguments, **kwargs):
    return subprocess.run([str(arg) for arg in arguments], capture_output=True, check=True, timeout=30, **kwargs).stdout


def png():
    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))
    header = struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0)
    scanlines = (b"\0" + bytes([45, 110, 89]) * 8) * 8
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b"")


def encrypt(key, data):
    return command("/usr/bin/openssl", "enc", "-aes-128-ecb", "-nosalt", "-K", key.hex(), input=data)


def ncm_container(audio, audio_format, cover=True):
    """A test-only container encoder, independent of the app's third-party decoder."""
    key = b"locally-generated-test-stream-key"
    encrypted_key = bytes(byte ^ 0x64 for byte in encrypt(CORE, KEY_PREFIX + key))
    metadata = {
        "musicName": "合成测试音频", "artist": [["测试歌手", 1]], "album": "测试专辑",
        "format": audio_format, "bitrate": 320000, "duration": 1250, "albumPic": "",
    }
    encoded_meta = METADATA_PREFIX + base64.b64encode(encrypt(META, b"music:" + json.dumps(metadata, ensure_ascii=False).encode()))
    encoded_meta = bytes(byte ^ 0x63 for byte in encoded_meta)
    box = list(range(256))
    last = key_index = 0
    for index in range(256):
        value = box[index]
        position = (value + last + key[key_index]) & 255
        key_index = (key_index + 1) % len(key)
        box[index] = box[position]
        box[position] = value
        last = position
    mask = bytearray()
    for index in range(256):
        j = (index + 1) & 255
        mask.append(box[(box[j] + box[(box[j] + j) & 255]) & 255])
    encrypted_audio = bytes(byte ^ mask[index % 256] for index, byte in enumerate(audio))
    image = png() if cover else b""
    padding = b"\0" * 32
    return (b"CTENFDAM\x01\x70" + struct.pack("<I", len(encrypted_key)) + encrypted_key
            + struct.pack("<I", len(encoded_meta)) + encoded_meta + b"\0" * 5
            + struct.pack("<II", len(image) + len(padding), len(image)) + image + padding + encrypted_audio)


def convert(*files, output=None):
    args = [str(CLI)]
    if output is not None:
        args.extend(["--output", str(output)])
    result = subprocess.run(args + [str(file) for file in files], env=ENV, capture_output=True, text=True, timeout=30)
    rows = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(rows) == len(files), (result.returncode, result.stdout, result.stderr)
    return result.returncode, rows


def probe(path):
    return json.loads(command(FFPROBE, "-v", "error", "-show_streams", "-show_format", "-of", "json", path))


def audio_hash(path):
    return command(FFMPEG, "-v", "error", "-i", path, "-map", "0:a:0", "-c:a", "copy", "-f", "hash", "-hash", "sha256", "-")


def main():
    assert CLI.exists() and APP.exists(), "先运行 python3 scripts/build.py"
    passed = []
    with tempfile.TemporaryDirectory(prefix="ncm2mp3-test-") as temporary:
        directory = Path(temporary)
        original_mp3 = directory / "generated.mp3"
        original_flac = directory / "generated.flac"
        command(FFMPEG, "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1.25", "-c:a", "libmp3lame", "-b:a", "192k", original_mp3)
        command(FFMPEG, "-v", "error", "-f", "lavfi", "-i", "sine=frequency=660:duration=1.25:sample_rate=96000", "-ac", "2", "-c:a", "flac", original_flac)

        source_mp3 = directory / "歌手 - 测试 空格🎵.NCM"
        source_flac = directory / "原始无损.ncm"
        source_mp3.write_bytes(ncm_container(original_mp3.read_bytes(), "mp3"))
        source_flac.write_bytes(ncm_container(original_flac.read_bytes(), "flac"))
        fingerprints = {source: hashlib.sha256(source.read_bytes()).digest() for source in [source_mp3, source_flac]}
        code, rows = convert(source_mp3, source_flac)
        assert code == 0 and all(row["status"] == "completed" for row in rows), rows
        assert rows[0]["transcoded"] is False and rows[1]["transcoded"] is True, rows
        for source in [source_mp3, source_flac]:
            target = source.with_suffix(".mp3")
            assert target.exists(), target
            data = probe(target)
            audio = next(stream for stream in data["streams"] if stream["codec_type"] == "audio")
            assert audio["codec_name"] == "mp3" and float(data["format"]["duration"]) > 1, data
            assert data["format"]["tags"].get("title") == "合成测试音频", data
            assert any(stream.get("disposition", {}).get("attached_pic") for stream in data["streams"]), data
            command(FFMPEG, "-v", "error", "-xerror", "-i", target, "-map", "0:a:0", "-f", "null", "-")
            assert hashlib.sha256(source.read_bytes()).digest() == fingerprints[source], "原文件发生变化"
        assert audio_hash(original_mp3) == audio_hash(source_mp3.with_suffix(".mp3")), "MP3 音频帧不应重编码"
        flac_output = next(stream for stream in probe(source_flac.with_suffix(".mp3"))["streams"] if stream["codec_type"] == "audio")
        assert flac_output["sample_rate"] == "44100" and int(flac_output["bit_rate"]) == 320000, flac_output
        passed.extend(["MP3 原音频帧保留", "96 kHz FLAC 转真实 320 kbps MP3", "中文/空格/emoji/大写扩展名", "歌曲标签及内置封面保留", "原始 NCM 不变"])

        existing = source_mp3.with_suffix(".mp3")
        before = existing.read_bytes()
        code, rows = convert(source_mp3)
        assert code == 0 and rows[0]["status"] == "skipped" and existing.read_bytes() == before, rows
        passed.append("同名 MP3 自动跳过且不覆盖")

        custom = directory / "自定义输出"
        custom.mkdir()
        code, rows = convert(source_flac, output=custom)
        assert code == 0 and (custom / "原始无损.mp3").exists(), rows
        passed.append("指定输出文件夹")

        streamed = command(FFMPEG, "-v", "error", "-f", "lavfi", "-i", "sine=frequency=550:duration=1.25", "-c:a", "flac", "-f", "flac", "-")
        unknown_duration = directory / "无时长头.ncm"
        unknown_duration.write_bytes(ncm_container(streamed, "flac"))
        code, rows = convert(unknown_duration)
        assert code == 0 and rows[0]["status"] == "completed", rows
        assert probe(unknown_duration.with_suffix(".mp3"))["format"]["duration"], rows
        passed.append("缺少头部时长的有效 FLAC")

        broken = directory / "损坏.ncm"
        broken.write_bytes(b"this is not an NCM file" * 4)
        truncated = directory / "截断.ncm"
        truncated.write_bytes(source_mp3.read_bytes()[:40])
        enormous = directory / "错误长度.ncm"
        enormous.write_bytes(b"CTENFDAM\x01\x70" + struct.pack("<I", 0xFFFFFFFF) + b"0" * 100)
        no_audio = directory / "错误音轨.ncm"
        no_audio.write_bytes(ncm_container(b"invalid audio bytes" * 20, "flac", cover=False))
        valid_after_error = directory / "队列继续.ncm"
        valid_after_error.write_bytes(ncm_container(original_mp3.read_bytes(), "mp3", cover=False))
        code, rows = convert(broken, truncated, enormous, no_audio, valid_after_error, output=custom)
        assert code == 1 and [row["status"] for row in rows] == ["failed"] * 4 + ["completed"], rows
        assert not any((custom / source.with_suffix(".mp3").name).exists() for source in [broken, truncated, enormous, no_audio])
        passed.extend(["无效/截断/异常长度/假音轨拒绝输出", "单文件失败后继续批量队列", "无内置封面也可离线转换"])

        missing_folder = directory / "不存在"
        code, rows = convert(source_mp3, output=missing_folder)
        assert code == 1 and rows[0]["status"] == "failed", rows
        assert not list(directory.glob(".ncm2mp3-*")) and not list(custom.glob(".ncm2mp3-*")), "临时输出未清理"
        passed.append("输出路径错误及临时文件清理")

    for item in passed:
        print("PASS " + item)
    print(f"通过 {len(passed)} 项集成验证。")


if __name__ == "__main__":
    main()
