#!/usr/bin/env python3
"""Build the local Apple Silicon app without Xcode project files or third-party Python packages."""
from pathlib import Path
import hashlib
import json
import platform
import plistlib
import shutil
import subprocess
import urllib.request
import zipfile
import io

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
APP = BUILD / "NCM 转 MP3.app"
OUTPUT_APP = ROOT / "dist" / "NCM 转 MP3.app"
VENDOR = ROOT / "vendor"
VERSION = "1.5.1"
ARCHIVE_URL = f"https://github.com/taurusxin/ncmdump/releases/download/{VERSION}/ncmdump-{VERSION}-macos-arm64.zip"
ARCHIVE_SHA256 = "5b2888b8a53e7a817a75d4e79c872840e37f200b08394ec3b4370430347339c4"


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def prepare_dependencies():
    ncm = VENDOR / "ncmdump"
    ncm.mkdir(parents=True, exist_ok=True)
    if not (ncm / "ncmdump").exists():
        with urllib.request.urlopen(ARCHIVE_URL, timeout=30) as response:
            archive = response.read()
        if hashlib.sha256(archive).hexdigest() != ARCHIVE_SHA256:
            raise RuntimeError("ncmdump 官方发行包校验失败")
        with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
            member = next(name for name in bundle.namelist() if Path(name).name == "ncmdump")
            (ncm / "ncmdump").write_bytes(bundle.read(member))
        (ncm / "ncmdump").chmod(0o755)
    if not (ncm / "LICENSE.txt").exists():
        with urllib.request.urlopen(f"https://raw.githubusercontent.com/taurusxin/ncmdump/{VERSION}/LICENSE.txt", timeout=20) as response:
            (ncm / "LICENSE.txt").write_bytes(response.read())
    (ncm / "SOURCE.json").write_text(json.dumps({
        "project": "taurusxin/ncmdump", "version": VERSION,
        "url": ARCHIVE_URL, "archive_sha256": ARCHIVE_SHA256,
        "binary_sha256": hashlib.sha256((ncm / "ncmdump").read_bytes()).hexdigest(),
    }, indent=2) + "\n")

    tag = VENDOR / "taglib"
    tag.mkdir(parents=True, exist_ok=True)
    if not (tag / "libtag.2.dylib").exists():
        prefix = Path("/opt/homebrew/opt/taglib")
        if not (prefix / "lib/libtag.2.dylib").exists():
            raise RuntimeError("首次构建需要 TagLib：brew install taglib")
        shutil.copy2(prefix / "lib/libtag.2.dylib", tag / "libtag.2.dylib", follow_symlinks=True)
        for name in ["COPYING.LGPL", "COPYING.MPL", "AUTHORS", "README.md"]:
            shutil.copy2(prefix / name, tag / name)
        library_version = (prefix / "lib/libtag.2.dylib").resolve().name.removeprefix("libtag.").removesuffix(".dylib")
        (tag / "SOURCE.json").write_text(json.dumps({
            "project": "taglib/taglib", "version": library_version,
            "source": f"https://github.com/taglib/taglib/releases/tag/v{library_version}",
            "license": "MPL-1.1 OR LGPL-2.1-only",
            "binary_sha256": hashlib.sha256((tag / "libtag.2.dylib").read_bytes()).hexdigest(),
        }, indent=2) + "\n")


def main():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("当前构建脚本及附带组件适用于 Apple Silicon Mac。")
    prepare_dependencies()
    BUILD.mkdir(exist_ok=True)
    if APP.exists():
        shutil.rmtree(APP)
    contents = APP / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    binary_folder = resources / "bin"
    for folder in [macos, binary_folder]:
        folder.mkdir(parents=True, exist_ok=True)
    flags = ["-swift-version", "5", "-O", "-parse-as-library", "-target", "arm64-apple-macosx13.0"]
    print("正在编译转换核心和 macOS 界面…", flush=True)
    run("swiftc", *flags, "Sources/ConversionEngine.swift", "Sources/App.swift", "-o", macos / "NCMConverter")
    run("swiftc", *flags, "Sources/ConversionEngine.swift", "Sources/CLI.swift", "-o", BUILD / "ncm2mp3")

    shutil.copy2(VENDOR / "ncmdump/ncmdump", binary_folder / "ncmdump")
    shutil.copy2(VENDOR / "taglib/libtag.2.dylib", binary_folder / "libtag.2.dylib")
    (binary_folder / "libtag.2.dylib").chmod(0o755)
    run("install_name_tool", "-change", "/opt/homebrew/opt/taglib/lib/libtag.2.dylib", "@executable_path/libtag.2.dylib", binary_folder / "ncmdump")
    run("install_name_tool", "-id", "@rpath/libtag.2.dylib", binary_folder / "libtag.2.dylib")

    notices = resources / "ThirdParty"
    for name in ["ncmdump", "taglib"]:
        destination = notices / name
        destination.mkdir(parents=True, exist_ok=True)
        for source in (VENDOR / name).iterdir():
            if source.suffix != ".dylib" and source.name != "ncmdump":
                shutil.copy2(source, destination / source.name)
    shutil.copy2(ROOT / "THIRD_PARTY.md", notices / "THIRD_PARTY.md")

    run("swiftc", "scripts/Icon.swift", "-o", BUILD / "make-icon")
    run(BUILD / "make-icon", BUILD / "AppIcon.iconset")
    run("iconutil", "-c", "icns", BUILD / "AppIcon.iconset", "-o", resources / "AppIcon.icns")
    info = {
        "CFBundleName": "NCM 转 MP3", "CFBundleDisplayName": "NCM 转 MP3",
        "CFBundleExecutable": "NCMConverter", "CFBundleIdentifier": "local.ncm2mp3.desktop",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "2",
        "CFBundleIconFile": "AppIcon", "LSMinimumSystemVersion": "13.0",
        "LSApplicationCategoryType": "public.app-category.music", "NSHighResolutionCapable": True,
        "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleDocumentTypes": [{
            "CFBundleTypeName": "网易云 NCM 音频", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Alternate",
            "LSItemContentTypes": ["com.netease.ncm"], "CFBundleTypeExtensions": ["ncm"],
        }],
        "UTImportedTypeDeclarations": [{
            "UTTypeIdentifier": "com.netease.ncm", "UTTypeDescription": "网易云 NCM 音频",
            "UTTypeConformsTo": ["public.data"], "UTTypeTagSpecification": {"public.filename-extension": ["ncm"]},
        }],
    }
    with (contents / "Info.plist").open("wb") as output:
        plistlib.dump(info, output)
    for target in [binary_folder / "libtag.2.dylib", binary_folder / "ncmdump", APP]:
        run("codesign", "--force", "--sign", "-", target)
    run("codesign", "--verify", "--deep", "--strict", APP)
    OUTPUT_APP.parent.mkdir(exist_ok=True)
    if OUTPUT_APP.exists():
        shutil.rmtree(OUTPUT_APP)
    shutil.move(str(APP), str(OUTPUT_APP))
    print(f"已生成：{OUTPUT_APP}", flush=True)


if __name__ == "__main__":
    main()
