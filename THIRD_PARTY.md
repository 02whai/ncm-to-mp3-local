# 第三方组件

本工具直接调用现成的开源解密组件，没有自行实现生产用 NCM 解密算法。测试中的容器编码器仅用于生成合成测试数据。

原生二进制及浏览器 WASM 由构建脚本获取或生成，不进入源码仓库。首次构建完成后，转换过程在本机运行。

- **ncmdump 1.5.1** — taurusxin，MIT。使用官方 macOS arm64 发行包，SHA-256 校验值为 `5b2888b8a53e7a817a75d4e79c872840e37f200b08394ec3b4370430347339c4`。应用内仅将 TagLib 动态库引用路径改为随包路径。源码、官方发行包和许可：[源码及说明](https://github.com/taurusxin/ncmdump/tree/1.5.1)、[Release](https://github.com/taurusxin/ncmdump/releases/tag/1.5.1)、[MIT](https://github.com/taurusxin/ncmdump/blob/1.5.1/LICENSE.txt)。许可副本位于 `vendor/ncmdump/LICENSE.txt`。
- **TagLib 2.2.1** — TagLib contributors，`MPL-1.1 OR LGPL-2.1-only`。使用 Homebrew 安装的 arm64 动态库，应用内仅调整动态库标识；不修改源码。版本与源地址记录在 `vendor/taglib/SOURCE.json`，上游源码可从[对应发布页](https://github.com/taglib/taglib/releases/tag/v2.2.1)取得。原文许可 `COPYING.MPL`、`COPYING.LGPL` 及作者名单随应用一并提供。
- **FFmpeg / FFprobe** — 使用电脑上已有的安装，本应用不内嵌或分发 FFmpeg。FLAC 等音轨使用 `libmp3lame` 输出 MP3。[官方源码与文档](https://ffmpeg.org/)、[MP3 编码器说明](https://ffmpeg.org/ffmpeg-codecs.html#libmp3lame)。

应用内的组件许可与来源记录位于 `Contents/Resources/ThirdParty/`。

## 网页版

- **ncmdump-js 0.0.3**，MIT：[源码](https://github.com/ant-cave/ncmdump-js)。
- **@ffmpeg/ffmpeg 0.12.15**，MIT；**@ffmpeg/core 0.12.10**，GPL-2.0-or-later：[源码与构建工程](https://github.com/ffmpegwasm/ffmpeg.wasm)、[FFmpeg 源码](https://ffmpeg.org/download.html)。构建后的离线包包含该 WASM 组件，保留其独立许可。
- **React / React DOM**，MIT；**Vite**，MIT；**fflate**，MIT；**Lucide**，ISC。具体版本由 `web/package-lock.json` 锁定。

网页版静态资源随附 `licenses.txt`。界面动效方向参考 UI Motion 和 React Bits，由本项目独立实现；未复制这两个站点的组件源码。
