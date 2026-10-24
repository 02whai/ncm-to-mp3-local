import {dump, parseNcm} from 'ncmdump-js';
import {validateNcm, isMp3} from './ncm-input.js';

self.onmessage = async ({data}) => {
  let bytes;
  try {
    bytes = new Uint8Array(data.bytes);
    validateNcm(bytes);
  } catch (error) {
    self.postMessage({error:error?.message || 'NCM 文件不完整'});
    return;
  }
  try {
    const parsed = parseNcm(bytes);
    const mp3 = isMp3(parsed.audio);
    const flac = parsed.audio[0] === 0x66 && parsed.audio[1] === 0x4c && parsed.audio[2] === 0x61 && parsed.audio[3] === 0x43;
    if (!mp3 && !flac) throw new Error('未找到有效的 MP3 或 FLAC 音轨');
    // The upstream format detector expects an ID3 header. Preserve headerless MP3 frames directly.
    let buffer;
    if (mp3 && parsed.format !== 'mp3') {
      buffer = parsed.audio.slice().buffer;
    } else {
      const result = await dump(bytes, {filename:data.name.replace(/\.ncm$/i,''), fetchMissingCover:false});
      buffer = await result.blob.arrayBuffer();
    }
    self.postMessage({bytes:buffer, format:mp3 ? 'mp3' : 'flac'}, [buffer]);
  } catch {
    self.postMessage({error:'无法读取此 NCM 文件，请检查文件是否完整'});
  }
};
