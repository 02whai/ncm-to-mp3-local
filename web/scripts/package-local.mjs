import {cp,mkdir,rm,writeFile,chmod} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('..',import.meta.url));
const output = path.resolve(root,'../dist/NCM 网页版');
await rm(output,{recursive:true,force:true});
await mkdir(output,{recursive:true});
await cp(path.join(root,'dist'),output,{recursive:true});
await cp(path.join(root,'start.py'),path.join(output,'start.py'));
await writeFile(path.join(output,'启动.command'),`#!/bin/zsh
set -e
cd -- "\${0:A:h}"
for ncm_python in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if [[ -x "$ncm_python" ]]; then
    exec "$ncm_python" start.py
  fi
done
print '未找到 Python 3。'
read -k 1
`);
await chmod(path.join(output,'启动.command'),0o755);
await writeFile(path.join(output,'使用说明.txt'),`NCM 转 MP3 · 本地静态网页版

Mac：双击「启动.command」，浏览器会打开本机页面。
其他系统：运行 python3 start.py。

拖入 NCM 后自动转换，完成后点击下载。
音频在浏览器内处理，不需要账号，不需要联网，不上传文件。
关闭启动窗口或按 Ctrl+C 即可停止。

此文件夹包含全部网页和转换组件，可以整包复制到其他电脑。
`);
console.log(output);
