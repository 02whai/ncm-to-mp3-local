# NCM 转 MP3 · 网页版

React + Vite 的静态网页，文件通过浏览器的 File API 读取，使用 `ncmdump-js` 和单线程 `ffmpeg.wasm` 在浏览器内转换。没有音频上传接口，不向服务器发送原文件。

本项目仅在本地使用，不部署线上，不需要账号或登录。网页与转换组件全部随包提供，运行时无需网络。

## 使用

拖入一个或多个 `.ncm` 文件，或点击「选择文件」。自动转换后，可逐首下载同名 MP3；「下载全部」会把多个 MP3 打成 ZIP。

Mac 直接双击项目根目录的 `启动网页版.command`，或交付文件夹 `dist/NCM 网页版/启动.command`。其他系统可运行 `python3 start.py`。本机页面默认地址为 `http://127.0.0.1:8765/`；端口被占用时自动使用其他空闲端口。关闭启动窗口或按 Ctrl+C 即可停止。

原始音轨为 MP3 时保留原音频帧；FLAC 使用 LAME 编码成 44.1 kHz / 320 kbps MP3。保留可解析的歌名、歌手、专辑及内置封面，不联网补封面。单个文件失败不影响其他任务，支持停止、重试和清空结果。

网页下载位置由浏览器设置决定。桌面版可以直接保存到原文件旁边。

## 开发和构建

```sh
npm install
npm run dev
npm test
npm run build
npm run build:local
```

开发服务器使用 `http://127.0.0.1:5173/`。静态输出在 `dist/`；`npm run build:local` 生成完整离线包 `../dist/NCM 网页版/`。自带启动器只向 `127.0.0.1` 提供这些静态文件，没有转换后端。因浏览器对本地文件中的模块和 Worker 有限制，请用启动器打开。

FFmpeg 组件由 `scripts/prepare-core.mjs` 从锁定版本的 npm 包复制到本站，WASM 分为小于 25 MB 的文件块。浏览器首次转换 FLAC 时加载这些本站资源，并在本地组合为 WASM Blob，不依赖第三方 CDN。使用单线程 core，无需 SharedArrayBuffer 或跨域隔离头。

界面采用固定的 560 × 600 桌面卡片，窄屏按可用空间收缩。按钮、文件卡片和结果反馈尊重 `prefers-reduced-motion`。动效方向参考 [UI Motion 的叠层文件反馈](https://uimotion.fyi/docs/stacked-file-hover)和 [React Bits 的 Spotlight Card](https://reactbits.dev/components/spotlight-card)，由本项目的 CSS / React 实现。

## 验证

`npm test` 使用本项目生成的正弦波 NCM，实际调用现成开源库，检查 MP3 / FLAC 解密、元数据和封面、输入不变、损坏文件拒绝以及原文件名保留。音频完整性检查需要系统中可用的 FFmpeg / FFprobe。

已在 Chrome 里通过系统文件选择器进行实际批量转换：MP3 和 96 kHz FLAC 均成功输出 MP3，损坏输入独立报错。下载 ZIP 后再用本机 FFprobe / FFmpeg 验证：原 MP3 保持 192 kbps；FLAC 输出 44.1 kHz / 320 kbps；两首均保留歌曲标签和封面，完整解码通过。

浏览器内转换、下载结果验证均使用合成测试音频。实际网易云版本产生的 NCM 仍以用户文件转换结果为准。

## 第三方组件

- `ncmdump-js 0.0.3`，MIT：[源码](https://github.com/ant-cave/ncmdump-js)。
- `@ffmpeg/ffmpeg 0.12.15`，MIT；`@ffmpeg/core 0.12.10`，GPL-2.0-or-later：[对应源码及构建工程](https://github.com/ffmpegwasm/ffmpeg.wasm)、[上游 FFmpeg](https://ffmpeg.org/download.html)。
- React / React DOM，MIT；Vite，MIT；fflate，MIT；Lucide，ISC。

依赖版本由 `package-lock.json` 锁定。组件许可和源码链接随静态站点置于 `/licenses.txt`。
