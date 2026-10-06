(function(scope){
'use strict';
const groups=[['command','Command stream'],['submit','Submission / queue'],['shader','Shader workers'],['dxvkOther','Other DXVK']];
const n=x=>x===null||x===undefined||!Number.isFinite(Number(x))?null:Number(x);
function sample(d){const workers={};for(const [key] of groups){const g=d.graphics_workers?.[key];workers[key]={cpu:n(g?.cpu_ms_per_s),queue:n(g?.cpu_queue_ms_per_s),active:n(g?.active),count:n(g?.count),measured:n(g?.measured),queueMeasured:n(g?.queue_measured)}}return {at:Date.parse(d.generated_at),identity:[d.session,d.game_pid,d.app_profile?.session||''].join('|'),fps:n(d.app_profile?.fps),p95:n(d.app_profile?.p95_ms),gpu:n(d.gpu?.busy_percent),workers}}
function append(history,s,now=Date.now()){if(!Number.isFinite(s.at)||now-s.at>10000||s.at>now+5000)return history;if(history.length&&history.at(-1).identity!==s.identity)history=[];if(history.length&&s.at<=history.at(-1).at)return history;return [...history,s].filter(x=>s.at-x.at<=60000).slice(-120)}
const api={sample,append};if(typeof module!=='undefined')module.exports=api;if(!scope.document)return;
const doc=scope.document,$=id=>doc.getElementById(id);if(!$('graphicsActivityRows'))return;let history=[],last;
const fmt=x=>x===null?'—':x.toFixed(1);
function table(root,headers,rows){root.replaceChildren();const t=doc.createElement('table');t.className='deep-table';const h=doc.createElement('tr');for(const text of headers){const c=doc.createElement('th');c.textContent=text;h.append(c)}t.append(h);for(const row of rows){const tr=doc.createElement('tr');for(const text of row){const c=doc.createElement('td');c.textContent=text;tr.append(c)}t.append(tr)}root.append(t)}
function render(){const s=history.at(-1);if(!s){$('graphicsActivityStatus').textContent='Waiting for fresh graphics-worker samples.';return}const paused=Date.now()-s.at>10000;
 $('graphicsActivityStatus').textContent=`${paused?'Paused · last sample':'Live'} · ${new Date(s.at).toLocaleTimeString()} · ${fmt(s.fps)} FPS · present p95 ${fmt(s.p95)} ms · GPU busy ${fmt(s.gpu)}% · sampled CPU activity`;
 table($('graphicsActivityRows'),['DXVK worker group','CPU ms/s','CPU queue ms/s','Workers using CPU','CPU coverage','Queue coverage'],groups.map(([key,label])=>{const g=s.workers[key];return [label,fmt(g.cpu),fmt(g.queue),g.active===null?'—':String(g.active),g.count===null?'Unavailable':`${g.measured||0}/${g.count}`,g.count===null?'Unavailable':`${g.queueMeasured||0}/${g.count}`]}));
 table($('graphicsActivityHistory'),['Time','Present p95 ms','GPU %','Command CPU ms/s','Submit CPU / queue ms/s','Shader CPU ms/s','Shader workers using CPU'],history.slice(-20).reverse().map(x=>[new Date(x.at).toLocaleTimeString(),fmt(x.p95),fmt(x.gpu),fmt(x.workers.command.cpu),`${fmt(x.workers.submit.cpu)} / ${fmt(x.workers.submit.queue)}`,fmt(x.workers.shader.cpu),x.workers.shader.active===null?'—':String(x.workers.shader.active)]));
}
const original=scope.renderProfileData;scope.renderProfileData=d=>{original(d);last=d;const next=append(history,sample(d));if(next!==history){history=next;render()}};setInterval(()=>{if(last&&Date.now()-Date.parse(last.generated_at)>10000)render()},2000);if(scope.profileData)scope.renderProfileData(scope.profileData);
})(typeof window==='undefined'?globalThis:window);
