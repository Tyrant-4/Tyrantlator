/* Continuous live comparisons with an optional pinned baseline. No upload. */
(function(scope){
'use strict';
const fields=[['HUD FPS','fps','fps'],['App present p95','appP95','ms'],['Game CPU','cpu','busy cores'],['GPU busy','gpu','%'],['CPU temperature','temp','°C'],['Available RAM','ram','MB'],['Surface update p95','surfaceP95','ms']];
const numeric=x=>x!==null&&x!==undefined&&Number.isFinite(Number(x))?Number(x):null;
function identity(d){return [d.game,d.game_pid,d.container,d.backend,d.target_fps,d.app_profile?.session||''].join('|')}
function sample(d){return {at:d.generated_at,fps:numeric(d.app_profile?.fps),appP95:numeric(d.app_profile?.p95_ms),cpu:numeric(d.cpu?.game_ms_per_s)===null?null:d.cpu.game_ms_per_s/1000,gpu:numeric(d.gpu?.busy_percent),temp:numeric(d.thermal?.cpu_c),ram:numeric(d.memory?.available_mb),surfaceP95:numeric(d.surface?.p95_ms)}}
function summarize(samples){const result={};for(const [,key] of fields){const values=samples.map(s=>s[key]).filter(v=>v!==null&&Number.isFinite(v));result[key]={mean:values.length?values.reduce((a,b)=>a+b,0)/values.length:null,count:values.length}}return result}
const api={fields,identity,sample,summarize};if(typeof module!=='undefined')module.exports=api;
if(!scope.document)return;
const doc=scope.document,$=id=>doc.getElementById(id),format=x=>x===null?'Unavailable':x.toFixed(1);
let current=null,runs={A:null,B:null},recent=[],recentKey=null,storage=true;
try{const saved=JSON.parse(scope.localStorage.getItem('tyrantlator-comparisons-v1')||'null');if(saved&&saved.version===1){for(const slot of ['A','B']){const r=saved[slot];if(slot==='A'&&r&&Array.isArray(r.samples)&&r.samples.length>=5&&r.samples.length<=300&&typeof r.label==='string'&&Number.isFinite(r.duration)&&r.duration>=5&&typeof r.game==='string'&&r.samples.every(s=>s&&typeof s.at==='string'))runs[slot]=r}}}catch{storage=false}
function message(text){$('comparisonStatus').textContent=text}
function save(){try{scope.localStorage.setItem('tyrantlator-comparisons-v1',JSON.stringify({version:1,...runs}))}catch{storage=false}}
function render(){const root=$('comparisonResults');root.replaceChildren();const a=runs.A,b=runs.B;
 for(const [slot,r] of Object.entries(runs)){const p=doc.createElement('p');p.textContent=r?`${slot}: ${r.label} · ${r.game} · ${r.samples.length} samples · ${r.duration.toFixed(1)} s · ${new Date(r.saved).toLocaleString()}`:`${slot}: no saved recording`;root.append(p)}
 if(!a&&!b)return;
 const table=doc.createElement('table');table.className='deep-table';const header=doc.createElement('tr');for(const title of ['Average sampled reading','A','B','B − A']){const th=doc.createElement('th');th.textContent=title;header.append(th)}table.append(header);
 const sa=a?summarize(a.samples):null,sb=b?summarize(b.samples):null;
 for(const [label,key,unit] of fields){const va=sa?.[key]?.mean??null,vb=sb?.[key]?.mean??null,tr=doc.createElement('tr');for(const text of [label,`${format(va)}${va===null?'':' '+unit} (${sa?.[key]?.count||0})`,`${format(vb)}${vb===null?'':' '+unit} (${sb?.[key]?.count||0})`,va===null||vb===null?'—':`${vb-va>=0?'+':''}${(vb-va).toFixed(1)} ${unit}`]){const td=doc.createElement('td');td.textContent=text;tr.append(td)}table.append(tr)}root.append(table);
 if(a&&b){const p=doc.createElement('p');p.className='detail';p.textContent=a.game!==b.game||a.container!==b.container?'Different game or app: baseline and live readings are not directly comparable.':'Live values update continuously over the latest 30 seconds. Compare the same scene and change one setting. Differences are observations, not proof of a cause. Counts show valid samples. App p95 is an average of rolling p95 readings.';root.append(p)}
}
function accept(d){
 current=d;const age=Date.now()-Date.parse(d.generated_at),key=identity(d);
 if(!Number.isFinite(age)||age<0||age>10000||d.game==='Unavailable'){runs.B=null;render();message('Live game readings unavailable. Start the collector and a game.');return}
 if(key!==recentKey){recent=[];recentKey=key}
 recent=recent.filter(s=>Date.now()-Date.parse(s.at)<=30000);
 if(!recent.some(s=>s.at===d.generated_at))recent.push(sample(d));
 const duration=recent.length>1?(Date.parse(recent.at(-1).at)-Date.parse(recent[0].at))/1000:0;
 runs.B={label:'Continuously updating',game:d.game,container:d.container,backend:d.backend,target:d.target_fps,samples:recent.slice(),duration,saved:new Date().toISOString()};
 render();message(`Live monitoring � ${recent.length} fresh samples. Pin a baseline whenever you want to compare a change.`)
}
function pin(){
 if(!current||Date.now()-Date.parse(current.generated_at)>10000||!runs.B||recent.length<5||runs.B.duration<5){message('Need at least five fresh live samples spanning five seconds to pin a useful baseline. Live monitoring continues.');return}
 runs.A={...runs.B,label:$('runLabel').value.trim().slice(0,80)||'Pinned settings',samples:recent.slice()};save();render();message(`Baseline pinned. Live readings keep updating.${storage?' Saved in this browser.':' Export to keep this baseline.'}`)
}
function family(d){const root=$('processFamily');root.replaceChildren();const list=d.process_family||[];if(!list.length){root.textContent='No process family available. Start a game with the updated live collector.';return}
 const table=doc.createElement('table');table.className='deep-table';const head=doc.createElement('tr');for(const label of ['Process / PID','Relationship','State','CPU cores','RAM MB','Parent PID']){const cell=doc.createElement('th');cell.textContent=label;head.append(cell)}table.append(head);
 const states={R:'Running or ready',S:'Sleeping',D:'Blocked wait',Z:'Leader exited; threads may remain',T:'Stopped',t:'Tracing stop'};
 for(const p of list){const tr=doc.createElement('tr');for(const text of [`${p.name} (${p.pid})`,p.relation,states[p.state]||p.state,p.cpu_cores===null?'Warming up / unavailable':Number(p.cpu_cores).toFixed(2),p.rss_mb===null?'Unavailable':p.rss_mb,p.ppid]){const td=doc.createElement('td');td.textContent=text;tr.append(td)}table.append(tr)}root.append(table)
}
$('pinBaseline').onclick=pin;
$('clearComparisons').onclick=()=>{runs.A=null;save();render();message('Baseline cleared. Live monitoring continues.')};
$('exportComparisons').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify({version:1,...runs},null,2)],{type:'application/json'}));const a=doc.createElement('a');a.href=url;a.download='tyrantlator-live-comparison.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
setInterval(()=>{if(current&&Date.now()-Date.parse(current.generated_at)>10000){runs.B=null;render();message('Collector paused. Live comparison unavailable; pinned baseline kept.')}},1000);
const original=scope.renderProfileData;scope.renderProfileData=d=>{original(d);family(d);accept(d)};render();if(scope.profileData)scope.renderProfileData(scope.profileData);
})(typeof window==='undefined'?globalThis:window);
