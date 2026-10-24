import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {dump,parseNcm} from 'ncmdump-js';
import {validateNcm,mp3Filename,isMp3} from '../src/ncm-input.js';

for (const [name,format] of [['MP3 原音轨.NCM','mp3'],['FLAC 无损.ncm','flac']]) {
  test(`现成库还原 ${format}，保留标签及内置封面`, async () => {
    const source = new Uint8Array(await readFile(new URL('./fixtures/'+name,import.meta.url)));
    const original = source.slice();
    validateNcm(source);
    const info = parseNcm(source);
    assert.equal(info.format,format);
    assert.equal(info.metadata.musicName,'合成测试音频');
    assert.ok(info.image.length > 0);
    const result = await dump(source,{filename:name.replace(/\.ncm$/i,''),fetchMissingCover:false});
    assert.equal(result.extension,format);
    const audio = new Uint8Array(await result.blob.arrayBuffer());
    assert.equal(isMp3(audio),format === 'mp3');
    assert.deepEqual(source,original,'解密不应改写输入');
    const directory = await mkdtemp(path.join(tmpdir(),'ncm-web-'));
    try {
      const file = path.join(directory,'output.'+format);
      await writeFile(file,audio);
      const probe = JSON.parse(execFileSync(process.env.FFPROBE || 'ffprobe',['-v','error','-show_streams','-show_format','-of','json',file],{encoding:'utf8'}));
      assert.equal(probe.streams.find(item => item.codec_type === 'audio').codec_name,format);
      const tags = Object.fromEntries(Object.entries(probe.format.tags).map(([key,value]) => [key.toLowerCase(),value]));
      assert.equal(tags.title,'合成测试音频');
      assert.ok(probe.streams.some(item => item.disposition.attached_pic));
      execFileSync(process.env.FFMPEG || 'ffmpeg',['-v','error','-xerror','-i',file,'-map','0:a:0','-f','null','-']);
    } finally { await rm(directory,{recursive:true,force:true}); }
  });
}

test('损坏和截断的 NCM 在调用解密库前拒绝',async () => {
  const bytes = new Uint8Array(await readFile(new URL('./fixtures/MP3 原音轨.NCM',import.meta.url)));
  assert.throws(() => validateNcm(new Uint8Array(0)));
  assert.throws(() => validateNcm(bytes.subarray(0,40)));
  const enormous = bytes.slice();
  new DataView(enormous.buffer).setUint32(10,0xffffffff,true);
  assert.throws(() => validateNcm(enormous));
  const broken = new Uint8Array(await readFile(new URL('./fixtures/损坏文件.ncm',import.meta.url)));
  assert.throws(() => validateNcm(broken));
});

test('输出文件名仅替换扩展名',() => {
  assert.equal(mp3Filename('歌手 - 曲名 🎵.NCM'),'歌手 - 曲名 🎵.mp3');
  assert.equal(mp3Filename('a.b.ncm'),'a.b.mp3');
});

test('ID3 标签本身和随机字节不能被识别为有效 MP3',() => {
  assert.equal(isMp3(new Uint8Array([73,68,51,4,0,0,0,0,0,0])),false);
  assert.equal(isMp3(new Uint8Array(300)),false);
  assert.equal(isMp3(new Uint8Array([255,251,144,0,0,0,0,0])),true);
});
