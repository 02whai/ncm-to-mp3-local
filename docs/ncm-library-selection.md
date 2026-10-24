# NCM 小工具开源组件选型

核对日期：2026-10-24。原始需求：拖入 NCM，在本地生成同名 MP3。原生候选的详细源码核对见 [ncm-native-research.md](ncm-native-research.md)。

## 已采用

**ncmdump 1.5.1 CLI + FFmpeg，界面使用 SwiftUI / AppKit。** ncmdump 的 MIT 许可、官方 macOS arm64 发行包和简单的命令行接口适合当前环境；采用官方预编译组件，不自行重写 NCM 解密。它还原的是原始 MP3 或 FLAC，统一输出 MP3 的步骤交给 FFmpeg。[ncmdump 官方说明](https://github.com/taurusxin/ncmdump)、[官方 Release](https://github.com/taurusxin/ncmdump/releases/tag/1.5.1)、[MP3 编码器官方文档](https://ffmpeg.org/ffmpeg-codecs.html#libmp3lame)

本机下载的官方发行 ZIP 的 SHA-256 为 `5b2888b8a53e7a817a75d4e79c872840e37f200b08394ec3b4370430347339c4`，与 GitHub Release asset 的 `digest` 一致。`otool -L` 表明它依赖 TagLib；因此最终应用随包放置 TagLib 动态库，FFmpeg 和 FFprobe 使用本机已有的安装。[官方发布元数据](https://api.github.com/repos/taurusxin/ncmdump/releases/latest)

当前实现已经用合成的 MP3/FLAC 音频进行端到端转换验证，结果记录见项目 README；尚未使用用户自己的音乐文件验收。

## 另查到的 JS 库

- **[ant-cave/ncmdump-js](https://github.com/ant-cave/ncmdump-js)**：MIT，npm 最新版 0.0.3，发布于 2026-07-31。提供浏览器和 Node.js 的 `dump()` API、TypeScript 类型，支持写歌曲标签及封面；可通过 `fetchMissingCover: false` 关闭缺封面时的联网获取。适合纯网页方案，但它仍只是还原 MP3/FLAC，不能保证统一输出 MP3。源码只用 `ID3` 头识别 MP3，其余默认为 FLAC；对于当前本地桌面需求，现成的 macOS 原生 CLI 更直接。这是针对本次需求的选型判断，不等于已对所有输入做兼容性比较。[npm 一手元数据](https://registry.npmjs.org/ncmdump-js)、[库接口](https://github.com/ant-cave/ncmdump-js/blob/main/src/index.js)、[格式识别源码](https://github.com/ant-cave/ncmdump-js/blob/main/src/lib/ncm.js)
- **[ncm-decrypt](https://www.npmjs.com/package/ncm-decrypt)**：npm 0.0.4，发布于 2025-07-22。官方 README 表明仅支持 Node.js ESM，不支持浏览器；包元数据声明 ISC，而 README 写 MIT，许可证信息存在不一致。因此未选用，也未安装。[官方 npm 元数据及 README](https://registry.npmjs.org/ncm-decrypt)

## 现成桌面工具

- **[AkiroMusic/AkiConvert](https://github.com/AkiroMusic/AkiConvert)**：GPL-3.0，Electron 桌面工具，支持拖入文件、NCM、FFmpeg 转 MP3、标签/封面及本地处理；v2.2.2 发布页实际提供 macOS DMG（约 320 MB）。如果希望下载一个完整的多格式转换器，可以作为候选；对当前只要 NCM 拖拽转同名 MP3 的需求，功能范围更大。此处仅核对源码及官方发行信息，未安装试用该应用。[官方功能和构建说明](https://github.com/AkiroMusic/AkiConvert/blob/master/README.md)、[v2.2.2 下载](https://github.com/AkiroMusic/AkiConvert/releases/tag/v2.2.2)
- **[dragonbreaker233/ncm-converter](https://github.com/dragonbreaker233/ncm-converter)**：MIT，Python + tkinterdnd2 的现成拖拽 GUI。官方说明明确是纯解密，不重新编码；因此内部音轨为 FLAC 的 NCM 仍输出 FLAC，不直接满足“全部输出 MP3”。未安装试用。[官方说明](https://github.com/dragonbreaker233/ncm-converter/blob/master/README.md)

## 当前应用补齐的行为

1. NCM 解密后的真实编码经过 FFprobe 检查；原 MP3 直接保留，FLAC 等由 FFmpeg 重新编码。
2. 解密、转码在独立临时目录处理，原文件只读。
3. 转换结果经过完整音频解码验证；不只依赖 ncmdump 的退出码。
4. 沿用原文件 basename；已有同名 MP3 自动跳过，最终写入也禁止覆盖。
5. 接受 `.ncm` 和 `.NCM`，支持中文、空格及 emoji 文件名。
6. 不下载在线封面，全部处理在本机完成。
