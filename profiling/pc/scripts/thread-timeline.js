/* Rolling live samples, not an exact scheduler trace. */
(function(scope){
'use strict';
const value=x=>x===null||x===undefined||!Number.isFinite(Number(x))?null:Number(x);
function createHistory(){return {identity:null,samples:[]}}
function ingest(h,d,now=Date.now()){
 const at=Date.parse(d.generated_at),id=[d.session,d.game_pid,d.app_profile?.session||''].join('|');
 if(!Number.isFinite(at)||now-at>10000||at>now+5000)return false;
 if(h.identity!==id){h.identity=id;h.samples=[]}
 if(h.samples.length&&at<=h.samples.at(-1).at)return false;
 const threads=new Map();
 for(const t of d.game_threads?.timeline_rows||d.game_threads?.rows||[]){
  const key=[t.tid,t.start_token||'',t.name].join('|');threads.set(key,{...t,cpu:value(t.cpu_percent),queue:value(t.cpu_queue_ms_per_s)});
 }
 h.samples.push({at,threads,complete:Array.isArray(d.game_threads?.timeline_rows)&&d.game_threads?.timeline_complete!==false});
 h.samples=h.samples.filter(s=>at-s.at<=60000).slice(-120);return true;
}
function series(h){
 const all=new Map();for(const s of h.samples)for(const [key,t] of s.threads){if(!all.has(key))all.set(key,{key,thread:t,score:0});const r=all.get(key);r.thread=t;r.score+=(t.cpu||0)+(t.queue||0)/10}
 return [...all.values()].sort((a,b)=>b.score-a.score||a.thread.tid-b.thread.tid).slice(0,24).map(r=>({...r,points:h.samples.map(s=>s.threads.get(r.key)||null)}));
}
const api={createHistory,ingest,series};if(typeof module!=='undefined')module.exports=api;if(!scope.document)return;
const doc=scope.document,root=doc.getElementById('threadTimeline'),status=doc.getElementById('threadTimelineStatus');if(!root||!status)return;
const history=createHistory();let last;
function render(){
 root.replaceChildren();const rows=series(history),samples=history.samples;if(!samples.length){status.textContent='Waiting for fresh live thread samples.';return}
 const end=samples.at(-1).at,age=Date.now()-end,span=(end-samples[0].at)/1000;
 status.textContent=`${age>10000?'Paused · last samples':'Live'} · ${span.toFixed(0)} s history · ${rows.length} threads shown · ${samples.at(-1).complete?'all readable threads sampled':'partial thread coverage'}`;
 if(!rows.length){root.textContent='No readable game threads.';return}
 const table=doc.createElement('table');table.className='deep-table thread-history';const head=doc.createElement('tr');for(const label of ['Thread / TID','CPU work / queue wait · last 60 s → now','Latest CPU %','Queue ms/s','State / core']){const th=doc.createElement('th');th.textContent=label;head.append(th)}table.append(head);
 const start=end-60000;
 for(const row of rows){const tr=doc.createElement('tr'),name=doc.createElement('td');name.textContent=`${row.thread.name} (${row.thread.tid})`;tr.append(name);const td=doc.createElement('td'),strip=doc.createElement('div');strip.className='thread-strip';
  row.points.forEach((p,i)=>{const at=samples[i].at,prior=i?samples[i-1].at:at,width=Math.min(4000,Math.max(0,at-prior));if(!width)return;const cell=doc.createElement('span');cell.className='thread-sample';cell.style.left=`${Math.max(0,(at-width-start)/600)}%`;cell.style.width=`${width/600}%`;
   const cpu=doc.createElement('i'),queue=doc.createElement('i');cpu.className='thread-cpu';queue.className='thread-queue';cpu.style.opacity=p&&p.cpu!==null?String(.12+.88*Math.min(100,p.cpu)/100):'0';queue.style.opacity=p&&p.queue!==null?String(.12+.88*Math.min(1000,p.queue)/1000):'0';cell.title=`${new Date(at).toLocaleTimeString()} · ${p?'CPU '+(p.cpu===null?'unavailable':p.cpu.toFixed(1)+'%')+' · queue '+(p.queue===null?'unavailable':p.queue.toFixed(1)+' ms/s')+' · state '+p.state+' · C'+p.last_core:'Not sampled'}`;cell.append(cpu,queue);strip.append(cell)});
  td.append(strip);tr.append(td);const latest=row.points.at(-1);for(const text of [latest?.cpu===null||!latest?'—':latest.cpu.toFixed(1),latest?.queue===null||!latest?'—':latest.queue.toFixed(1),latest?`${latest.state} / C${latest.last_core}`:'Not sampled']){const c=doc.createElement('td');c.textContent=text;tr.append(c)}table.append(tr)
 }root.append(table);
}
const original=scope.renderProfileData;scope.renderProfileData=d=>{original(d);last=d;if(ingest(history,d))render()};setInterval(()=>{if(last&&Date.now()-Date.parse(last.generated_at)>10000)render()},2000);if(scope.profileData)scope.renderProfileData(scope.profileData);
})(typeof window==='undefined'?globalThis:window);
