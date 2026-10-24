import {FFmpeg} from '@ffmpeg/ffmpeg';
import {isMp3, mp3Filename} from './ncm-input.js';

const aborted = () => new DOMException('已停止', 'AbortError');

export class BrowserConverter {
  ffmpeg = null;
  loading = null;

  reset() {
    this.ffmpeg?.terminate();
    this.ffmpeg = null;
    this.loading = null;
  }

  async decrypt(file, signal) {
    const bytes = await file.arrayBuffer();
    if (signal.aborted) throw aborted();
    return new Promise((resolve,reject) => {
      const worker = new Worker(new URL('./decode.worker.js', import.meta.url), {type:'module'});
      const cleanup = () => { worker.terminate(); signal.removeEventListener('abort', stop); clearTimeout(timer); };
      const stop = () => { cleanup(); reject(aborted()); };
      const timer = setTimeout(() => { cleanup(); reject(new Error('读取文件超时，请重试')); }, 120000);
      signal.addEventListener('abort', stop, {once:true});
      worker.onmessage = ({data}) => {
        cleanup();
        if (data.error) reject(new Error(data.error));
        else resolve({bytes:new Uint8Array(data.bytes), format:data.format});
      };
      worker.onerror = () => { cleanup(); reject(new Error('无法读取此 NCM 文件')); };
      worker.postMessage({bytes,name:file.name}, [bytes]);
    });
  }

  async load(signal) {
    if (this.ffmpeg?.loaded) return this.ffmpeg;
    if (!this.loading) {
      const instance = new FFmpeg();
      this.ffmpeg = instance;
      this.loading = (async () => {
        const base = new URL('/ffmpeg/', window.location.origin);
        const response = await fetch(new URL('manifest.json', base), {signal, cache:'force-cache'});
        if (!response.ok) throw new Error('转换器加载失败，请重试');
        const manifest = await response.json();
        const chunks = await Promise.all(manifest.chunks.map(async chunk => {
          const result = await fetch(new URL(chunk.name, base), {signal, cache:'force-cache'});
          if (!result.ok) throw new Error('转换器加载失败，请重试');
          const data = await result.arrayBuffer();
          if (data.byteLength !== chunk.bytes) throw new Error('转换器文件不完整，请刷新重试');
          return data;
        }));
        const wasmURL = URL.createObjectURL(new Blob(chunks, {type:'application/wasm'}));
        try {
          await instance.load({coreURL:new URL('ffmpeg-core.js', base).href, wasmURL});
          if (signal.aborted) throw aborted();
          return instance;
        } finally { URL.revokeObjectURL(wasmURL); }
      })().catch(error => {
        if (this.ffmpeg === instance) this.reset();
        throw error;
      });
    }
    return this.loading;
  }

  async convert(file, {signal, onStage}) {
    onStage('正在读取', null);
    const decoded = await this.decrypt(file, signal);
    if (signal.aborted) throw aborted();
    let output;
    if (decoded.format === 'mp3') {
      output = decoded.bytes;
    } else {
      onStage('准备转换器', null);
      const stop = () => this.reset();
      signal.addEventListener('abort', stop, {once:true});
      let instance;
      const input = 'input-' + crypto.randomUUID() + '.flac';
      const result = 'output-' + crypto.randomUUID() + '.mp3';
      const progress = ({progress}) => onStage('正在转换', Math.max(0, Math.min(0.99, progress)));
      try {
        instance = await this.load(signal);
        if (signal.aborted) throw aborted();
        instance.on('progress', progress);
        onStage('正在转换', 0);
        await instance.writeFile(input, decoded.bytes);
        const status = await instance.exec([
          '-hide_banner','-v','error','-xerror','-i',input,'-map','0:a:0','-map','0:v?',
          '-map_metadata','0','-c:a','libmp3lame','-b:a','320k','-ar','44100','-ac','2',
          '-c:v','copy','-id3v2_version','3','-write_id3v1','1',result,
        ], 300000);
        if (status !== 0) throw new Error('无法转换此音轨，请检查文件是否完整');
        output = await instance.readFile(result);
      } catch (error) {
        if (signal.aborted) throw aborted();
        throw error;
      } finally {
        signal.removeEventListener('abort', stop);
        if (instance) {
          instance.off('progress', progress);
          if (instance.loaded) {
            await instance.deleteFile(input).catch(() => {});
            await instance.deleteFile(result).catch(() => {});
          }
        }
      }
    }
    if (signal.aborted) throw aborted();
    if (!(output instanceof Uint8Array) || !isMp3(output)) throw new Error('MP3 音轨校验失败');
    return {blob:new Blob([output], {type:'audio/mpeg'}), filename:mp3Filename(file.name)};
  }
}
