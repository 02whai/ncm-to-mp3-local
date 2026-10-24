# NCM 原生/命令行开源方案核对

核对日期：2026-10-24。需求：macOS 拖入 `.ncm`，在本地生成同名、实际编码为 MP3 的音频。以下依据项目官方仓库、源码和包注册页核对；此份笔记未运行真实歌曲转换，也未安装依赖。

## 结论

优先复用 **[taurusxin/ncmdump](https://github.com/taurusxin/ncmdump)** 的 C++ 命令行程序，用原生 macOS 界面封装，再用 FFmpeg 处理解出的 FLAC。其仓库仍可维护、提供 Apple Silicon 预编译程序，且无需 Python 环境。若希望把解密直接编进应用，Rust 的 **[iqiziqi/ncmdump.rs](https://github.com/iqiziqi/ncmdump.rs)** 库接口更直接，但项目更新较慢。[C++ 官方说明](https://github.com/taurusxin/ncmdump/blob/main/README.md)、[C++ 发布页](https://github.com/taurusxin/ncmdump/releases/tag/1.5.1)、[Rust 库文档](https://docs.rs/ncmdump/0.8.0/ncmdump/)

**解开 NCM 不等于一定得到 MP3。** 这些项目恢复的是 NCM 内原有的 MP3 或 FLAC 字节。为满足统一输出 `.mp3`：原音轨为 MP3 时直接保留；原音轨为 FLAC 时调用 FFmpeg 的 MP3 编码器重新编码。仅把 FLAC 的扩展名改成 `.mp3` 不会改变编码。[C++ Dump 源码](https://github.com/taurusxin/ncmdump/blob/main/src/ncmcrypt.cpp)、[Python 输出逻辑](https://github.com/ww-rm/ncmdump-py/blob/main/ncmdump/core.py)、[FFmpeg MP3 编码文档](https://ffmpeg.org/ffmpeg-codecs.html#libmp3lame)

## 候选比较

| 项目 | 许可与维护情况 | 接入方式 | 音频和元数据 | 对当前需求的判断 |
| --- | --- | --- | --- | --- |
| [taurusxin/ncmdump](https://github.com/taurusxin/ncmdump) | MIT；未归档；GitHub API 的最近仓库推送为 2026-08-20；最新正式版 1.5.1 发布于 2025-10-05 | 调用 CLI；1.5.1 提供 macOS arm64 程序；macOS 从源码构建需 CMake、TagLib | 恢复 MP3/FLAC；用 TagLib 写歌名、歌手、专辑及已有封面；不下载缺失封面 | 当前优先，适合 SwiftUI/AppKit 小界面包装 |
| [iqiziqi/ncmdump.rs](https://github.com/iqiziqi/ncmdump.rs) | Cargo 清单声明 MIT；未归档；最近仓库推送 2024-10-14；0.8.0 发布于 2024-09-17 | 可作为 Rust crate 引入；另有 CLI；官方发布包含 macOS arm64 和 x64 | 库提供 `from_reader`、`get_info`、`get_image`、`get_data`，并实现流式 `Read`；CLI 另实现 MP3/FLAC 标签写入 | 若做 Rust/Tauri 应用值得考虑；更新时间较早 |
| [ww-rm/ncmdump-py](https://github.com/ww-rm/ncmdump-py) | MIT；未归档；最近推送 2025-10-23；PyPI 1.1.6 同日发布 | `pip install ncmdump-py`；Python API 或 `python -m ncmdump` | 恢复 MP3/FLAC，自动写标签/封面；缺封面会尝试联网下载 | API 简洁，但严格离线及新版 Python 兼容性需要额外适配，当前不优先 |

维护数据来源：[C++ 仓库 API](https://api.github.com/repos/taurusxin/ncmdump)、[C++ 发布 API](https://api.github.com/repos/taurusxin/ncmdump/releases/latest)、[Rust 仓库 API](https://api.github.com/repos/iqiziqi/ncmdump.rs)、[Rust 发布页](https://github.com/iqiziqi/ncmdump.rs/releases/tag/0.8.0)、[Python 仓库 API](https://api.github.com/repos/ww-rm/ncmdump-py)、[PyPI](https://pypi.org/project/ncmdump-py/)。这里的“最近仓库推送”是 `pushed_at`，并不等于最近主分支代码修改日期。

许可与功能来源：[C++ LICENSE](https://github.com/taurusxin/ncmdump/blob/main/LICENSE.txt)、[C++ CMake 构建](https://github.com/taurusxin/ncmdump/blob/main/CMakeLists.txt)、[C++ 解密和标签实现](https://github.com/taurusxin/ncmdump/blob/main/src/ncmcrypt.cpp)、[Rust Cargo 清单](https://github.com/iqiziqi/ncmdump.rs/blob/master/Cargo.toml)、[Rust 核心实现](https://github.com/iqiziqi/ncmdump.rs/blob/master/crates/ncmdump/src/ncmdump.rs)、[Rust CLI 标签实现](https://github.com/iqiziqi/ncmdump.rs/blob/master/crates/ncmdump-bin/src/metadata.rs)、[Python LICENSE](https://github.com/ww-rm/ncmdump-py/blob/main/LICENSE)、[Python 核心实现](https://github.com/ww-rm/ncmdump-py/blob/main/ncmdump/core.py)。

## 封装 C++ ncmdump 时必须处理的行为

- **默认保存位置与名称**：`Dump()` 默认使用输入文件的路径，将扩展名换成 `.mp3` 或 `.flac`；`-o` 可以指定输出目录。[Dump 源码](https://github.com/taurusxin/ncmdump/blob/main/src/ncmcrypt.cpp)、[CLI 参数](https://github.com/taurusxin/ncmdump/blob/main/src/main.cpp)
- **错误退出码不可靠**：`processFile()` 遇到无效 NCM 或解密异常时只输出错误；`main()` 在逐个文件处理后仍可能返回 0。界面不能仅靠进程退出码宣布成功，应检查预期文件确实生成，并用 FFprobe/解码确认音轨有效。[CLI 源码](https://github.com/taurusxin/ncmdump/blob/main/src/main.cpp)
- **同名文件会覆盖**：输出使用 `std::ofstream` 的 `out | binary` 模式；建议每次解包到独立临时目录，验证后再移动到目标位置并处理已存在的同名 MP3。[Dump 源码](https://github.com/taurusxin/ncmdump/blob/main/src/ncmcrypt.cpp)
- **大小写扩展名**：CLI 严格判断输入扩展名为 `.ncm`；`.NCM` 会被跳过。可以在临时工作目录统一命名后再调用。[CLI 源码](https://github.com/taurusxin/ncmdump/blob/main/src/main.cpp)
- **离线处理**：解密、标签与封面写入均是本地文件操作；项目 README 明确解释未引入网络库，因此没有内置封面的输入会缺少封面。现有代码及构建依赖中未见下载行为。[README 封面说明](https://github.com/taurusxin/ncmdump/blob/main/README.md)、[核心源码](https://github.com/taurusxin/ncmdump/blob/main/src/ncmcrypt.cpp)、[构建定义](https://github.com/taurusxin/ncmdump/blob/main/CMakeLists.txt)
- **macOS 用 CLI 接入**：官方构建的共享库只在 `WIN32` 分支定义；macOS 分支只构建命令行程序。[CMakeLists.txt](https://github.com/taurusxin/ncmdump/blob/main/CMakeLists.txt)

## Python 候选的实际限制

`ncmdump-py` 官方示例的 `NeteaseCloudMusicFile(path).decrypt().dump_music(path)` 能直接调用，但 `dump_music()` 按元数据中的原始格式决定扩展名，不承诺 MP3。`decrypt()` 固定调用 `_try_get_cover_data()`；缺封面时使用没有显式超时的 `urlopen()`，也没有公开的离线开关。此外顶层 `import imghdr` 与 Python 3.13+ 标准库不兼容，虽然包元数据仅声明 Python >=3.7。[Python 核心代码](https://github.com/ww-rm/ncmdump-py/blob/main/ncmdump/core.py)、[包清单](https://github.com/ww-rm/ncmdump-py/blob/main/pyproject.toml)、[Python 官方 imghdr 移除说明](https://docs.python.org/3/library/imghdr.html)

## 另查到的替代

- [taurusxin/ncmdump-go](https://git.taurusxin.com/taurusxin/ncmdump-go)：作者自己的 Go 移植，MIT，官方页面显示 1.7.5 发布于 2025-11-25；有 `ncmcrypt.NewNeteaseCloudMusic()`、`Dump()` 和 `FixMetadata(false)` API，最后一个参数可关闭远程封面获取。可以复用，但当前 macOS 小界面使用已有 C++ CLI 更省事。[官方 README](https://git.taurusxin.com/taurusxin/ncmdump-go)、[Go 核心源码](https://git.taurusxin.com/taurusxin/ncmdump-go/src/branch/main/ncmcrypt/ncmcrypt.go)、[LICENSE](https://git.taurusxin.com/taurusxin/ncmdump-go/src/branch/main/LICENSE)
- [lkhsss/ncmmiao](https://github.com/lkhsss/ncmmiao)：更新更近期的 Rust 项目，crates.io 的 3.14.0 发布于 2026-09-01，声明 GPL-3.0-or-later；公开库 API 包含取消及进度信号。因当前方案已可直接利用体积很小的 C++ CLI，这里不继续扩展选型。[crates.io 一手元数据](https://crates.io/api/v1/crates/ncmmiao)、[公开库文档](https://docs.rs/ncmmiao/3.14.0/ncmmiao/)

实际兼容范围仍需用用户手头 NCM 样本验证；以上是源代码与发布信息核对，并非真实音乐样本的验收结论。
