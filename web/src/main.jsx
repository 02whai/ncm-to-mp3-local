import React, {useEffect, useRef, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {ArrowDown, ArrowRight, AudioWaveform as Waveform, Check, Download, FileAudio2, ListMusic, LoaderCircle, Music2, Plus, RotateCcw, X} from 'lucide-react';
import {zipSync} from 'fflate';
import {BrowserConverter} from './converter.js';
import {formatBytes} from './ncm-input.js';
import './style.css';

function saveBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

function FileFan({active}) {
  return <div className={'file-fan' + (active ? ' expanded' : '')} aria-hidden="true">
    <div className="stack-card back-left"><Waveform size={26}/></div>
    <div className="stack-card back-right"><Music2 size={26}/></div>
    <div className="stack-card front">{active ? <ArrowDown size={27}/> : <FileAudio2 size={29}/>}</div>
  </div>;
}

function App() {
  const [jobs,setJobs] = useState([]);
  const [dragging,setDragging] = useState(false);
  const [hovered,setHovered] = useState(false);
  const [notice,setNotice] = useState('');
  const [packing,setPacking] = useState(false);
  const jobsRef = useRef([]);
  const busy = useRef(false);
  const active = useRef(null);
  const engine = useRef(null);
  const input = useRef(null);
  const dragDepth = useRef(0);

  if (!engine.current) engine.current = new BrowserConverter();
  const update = transform => {
    jobsRef.current = transform(jobsRef.current);
    setJobs(jobsRef.current);
  };
  const patch = (id, values) => update(items => items.map(item => item.id === id ? {...item,...values} : item));

  async function drain() {
    if (busy.current) return;
    busy.current = true;
    try {
      let job;
      while ((job = jobsRef.current.find(item => item.state === 'waiting'))) {
        const controller = new AbortController();
        active.current = controller;
        patch(job.id, {state:'working',stage:'正在读取',progress:null,error:''});
        try {
          const result = await engine.current.convert(job.file, {
            signal:controller.signal,
            onStage:(stage,progress) => patch(job.id, {stage,progress}),
          });
          patch(job.id, {state:'completed',stage:'已完成',progress:1,blob:result.blob,filename:result.filename});
        } catch (error) {
          const stopped = error.name === 'AbortError';
          patch(job.id, {state:stopped ? 'cancelled' : 'failed',stage:stopped ? '已停止' : '转换失败',error:stopped ? '' : error.message});
        } finally { active.current = null; }
      }
    } finally { busy.current = false; }
  }

  function addFiles(files) {
    let invalid = 0;
    update(items => {
      const next = [...items];
      for (const file of files) {
        if (!/\.ncm$/i.test(file.name)) { invalid++; continue; }
        const key = `${file.name}:${file.size}:${file.lastModified}`;
        const previous = next.find(item => item.key === key);
        if (previous) continue;
        next.push({id:crypto.randomUUID(),key,file,filename:file.name,state:'waiting',stage:'等待转换',progress:null});
      }
      return next;
    });
    setNotice(invalid ? `已忽略 ${invalid} 个非 NCM 文件` : '');
    void drain();
  }

  function stop() {
    update(items => items.map(item => item.state === 'waiting' ? {...item,state:'cancelled',stage:'已停止'} : item));
    active.current?.abort();
  }

  function retry(id) {
    update(items => items.map(item => (!id || item.id === id) && ['failed','cancelled'].includes(item.state)
      ? {...item,state:'waiting',stage:'等待转换',error:'',progress:null} : item));
    void drain();
  }

  function clear() { update(items => items.filter(item => ['waiting','working'].includes(item.state))); }

  async function downloadAll() {
    const ready = jobsRef.current.filter(item => item.state === 'completed');
    if (ready.length === 1) { saveBlob(ready[0].blob,ready[0].filename); return; }
    setPacking(true);
    try {
      const files = Object.create(null);
      for (const item of ready) {
        let name = item.filename;
        let suffix = 2;
        while (files[name]) name = item.filename.replace(/\.mp3$/,` (${suffix++}).mp3`);
        files[name] = new Uint8Array(await item.blob.arrayBuffer());
      }
      saveBlob(new Blob([zipSync(files,{level:0})],{type:'application/zip'}),'NCM 转 MP3.zip');
    } catch { setNotice('打包失败，请分别下载文件'); }
    finally { setPacking(false); }
  }

  useEffect(() => {
    const prevent = event => { if ([...event.dataTransfer?.types ?? []].includes('Files')) event.preventDefault(); };
    window.addEventListener('dragover',prevent);
    window.addEventListener('drop',prevent);
    return () => {
      window.removeEventListener('dragover',prevent);
      window.removeEventListener('drop',prevent);
      active.current?.abort();
      engine.current?.reset();
    };
  },[]);

  const working = jobs.some(item => item.state === 'working');
  const completed = jobs.filter(item => item.state === 'completed').length;
  const canRetry = jobs.some(item => ['failed','cancelled'].includes(item.state));
  const canClear = jobs.some(item => !['waiting','working'].includes(item.state));

  return <main className="page">
    <section className="converter" aria-label="NCM 转 MP3">
      <header className="app-header">
        <div className="app-mark" aria-hidden="true"><Waveform size={21}/></div>
        <h1>NCM <ArrowRight aria-label="转为" size={20}/> MP3</h1>
      </header>

      <div className={'drop-zone' + (dragging ? ' dragging' : '')}
        onPointerEnter={() => setHovered(true)} onPointerLeave={() => setHovered(false)}
        onPointerMove={event => {
          const box = event.currentTarget.getBoundingClientRect();
          event.currentTarget.style.setProperty('--mx',`${event.clientX-box.left}px`);
          event.currentTarget.style.setProperty('--my',`${event.clientY-box.top}px`);
        }}
        onDragEnter={event => { event.preventDefault(); dragDepth.current++; setDragging(true); }}
        onDragLeave={event => { event.preventDefault(); dragDepth.current--; if (dragDepth.current <= 0) setDragging(false); }}
        onDragOver={event => { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; }}
        onDrop={event => { event.preventDefault(); dragDepth.current = 0; setDragging(false); addFiles([...event.dataTransfer.files]); }}
        data-testid="drop-zone">
        <FileFan active={dragging || hovered}/>
        <h2>{dragging ? '松开转换' : '拖入 NCM 文件'}</h2>
        <button className="choose-button" onClick={() => input.current.click()}><Plus size={16}/>选择文件</button>
        <input ref={input} type="file" accept=".ncm" multiple aria-label="选择 NCM 文件" aria-hidden="true" tabIndex={-1} className="file-input"
          onChange={event => { addFiles([...event.target.files]); event.target.value = ''; }}/>
      </div>

      {notice && <div role="alert" className="notice"><span>{notice}</span><button aria-label="关闭提示" onClick={() => setNotice('')}><X size={14}/></button></div>}

      <div className="queue-heading">
        <h2>文件{jobs.length > 0 && <span>{jobs.length}</span>}</h2>
        <div className="queue-actions">
          {completed > 0 && <span className="completed-count">已完成 {completed}</span>}
          {working ? <button onClick={stop}>停止</button> : canRetry && <button onClick={() => retry()}>重试</button>}
          {canClear && <button onClick={clear}>清空</button>}
        </div>
      </div>

      <div className="queue" aria-live="polite" aria-relevant="additions text" data-testid="conversion-list">
        {jobs.length === 0 ? <div className="empty-queue" aria-label="暂无文件"><ListMusic size={28} strokeWidth={1.2}/></div> :
          jobs.map(job => <div className={'job '+job.state} key={job.id} data-testid="conversion-row">
            <div className="job-symbol" aria-hidden="true">
              {job.state === 'working' ? <LoaderCircle size={20} className="spinner"/> : job.state === 'completed' ? <Check size={20}/> : job.state === 'failed' ? <X size={19}/> : <FileAudio2 size={20}/>}
            </div>
            <div className="job-content">
              <div className="job-filename" title={job.filename}>{job.filename}</div>
              <div className="job-detail" title={job.error || job.stage}>
                {job.error || job.stage}{job.state === 'completed' && <span> · {formatBytes(job.blob.size)}</span>}
                {job.state === 'working' && job.progress !== null && <span> {Math.round(job.progress * 100)}%</span>}
              </div>
              {job.state === 'working' && <div className={'progress-track'+(job.progress === null ? ' indeterminate' : '')} role="progressbar"
                aria-label={job.stage} aria-valuemin="0" aria-valuemax="100" aria-valuenow={job.progress === null ? undefined : Math.round(job.progress*100)}>
                <span style={job.progress === null ? {} : {width:`${job.progress*100}%`}}/>
              </div>}
            </div>
            {job.state === 'completed' && <button className="icon-button" aria-label={`下载 ${job.filename}`} title="下载 MP3" onClick={() => saveBlob(job.blob,job.filename)}><Download size={18}/></button>}
            {['failed','cancelled'].includes(job.state) && <button className="icon-button" aria-label={`重试 ${job.filename}`} title="重试" onClick={() => retry(job.id)}><RotateCcw size={17}/></button>}
          </div>)}
      </div>

      {completed > 0 && <button className="download-all" onClick={downloadAll} disabled={packing}>
        {packing ? <LoaderCircle className="spinner" size={16}/> : <Download size={16}/>}
        {packing ? '正在打包' : completed === 1 ? '下载 MP3' : `下载全部 · ${completed}`}
      </button>}
    </section>
  </main>;
}

createRoot(document.getElementById('root')).render(<App/>);
