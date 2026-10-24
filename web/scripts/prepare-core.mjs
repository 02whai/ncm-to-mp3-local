import {readFile, writeFile, mkdir, copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('..', import.meta.url));
const source = path.join(root, 'node_modules/@ffmpeg/core/dist/esm');
const target = path.join(root, 'public/ffmpeg');
await mkdir(target, {recursive:true});
const wasm = await readFile(path.join(source, 'ffmpeg-core.wasm'));
const hash = createHash('sha256').update(wasm).digest('hex');
let manifest;
try { manifest = JSON.parse(await readFile(path.join(target, 'manifest.json'), 'utf8')); } catch {}
if (manifest?.sha256 !== hash) {
  const chunks = [];
  const size = 16 * 1024 * 1024;
  for (let offset = 0; offset < wasm.length; offset += size) {
    const name = `ffmpeg-core.wasm.part-${chunks.length}`;
    const bytes = wasm.subarray(offset, offset + size);
    await writeFile(path.join(target, name), bytes);
    chunks.push({name, bytes:bytes.length});
  }
  await writeFile(path.join(target, 'manifest.json'), JSON.stringify({version:'0.12.10',sha256:hash,bytes:wasm.length,chunks}));
}
await copyFile(path.join(source, 'ffmpeg-core.js'), path.join(target, 'ffmpeg-core.js'));
console.log('FFmpeg 浏览器组件已准备');
