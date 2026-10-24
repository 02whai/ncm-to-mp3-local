export function validateNcm(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 32) throw new Error('NCM 文件不完整');
  const magic = [0x43,0x54,0x45,0x4e,0x46,0x44,0x41,0x4d];
  if (!magic.every((byte,index) => bytes[index] === byte)) throw new Error('这不是有效的 NCM 文件');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 10;
  const readLength = () => {
    if (offset + 4 > bytes.length) throw new Error('NCM 文件已截断');
    const value = view.getUint32(offset, true);
    offset += 4;
    return value;
  };
  const key = readLength();
  if (key < 32 || key > 65536 || key % 16 || offset + key > bytes.length) throw new Error('NCM 密钥数据已损坏');
  offset += key;
  const metadata = readLength();
  if ((metadata !== 0 && metadata < 46) || metadata > 16 * 1024 * 1024 || offset + metadata > bytes.length) throw new Error('NCM 歌曲信息已损坏');
  offset += metadata + 5;
  const frame = readLength();
  const image = readLength();
  if (image > frame || offset + frame >= bytes.length) throw new Error('NCM 音频数据不完整');
}

export function mp3Filename(name) {
  return name.replace(/\.ncm$/i, '') + '.mp3';
}

export function isMp3(bytes) {
  let offset = 0;
  if (bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
    if (bytes.length < 10) return false;
    offset = 10 + ((bytes[6] & 127) << 21 | (bytes[7] & 127) << 14 | (bytes[8] & 127) << 7 | bytes[9] & 127);
    if (bytes[5] & 0x10) offset += 10;
  }
  const end = Math.min(bytes.length - 3, offset + 4096);
  for (; offset < end; offset++) {
    const a = bytes[offset], b = bytes[offset + 1], c = bytes[offset + 2];
    if (a === 255 && (b & 224) === 224 && (b & 24) !== 8 && (b & 6) === 2 && (c >> 4) > 0 && (c >> 4) < 15 && (c & 12) !== 12) return true;
  }
  return false;
}

export function formatBytes(bytes) {
  if (bytes < 1024 * 1024) return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}
