const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const api=require('../scripts/thread-timeline.js');
let now=Date.parse('2026-10-06T01:00:00Z');
function data(tid=10,start='100',cpu=80,queue=200){return {session:'collector',game_pid:5,generated_at:new Date(now).toISOString(),game_threads:{timeline_rows:[{tid,start_token:start,name:'worker',cpu_percent:cpu,cpu_queue_ms_per_s:queue,state:'R',last_core:6}]}}}
const h=api.createHistory();assert.equal(api.ingest(h,data(),now),true);assert.equal(api.ingest(h,data(),now),false);
now+=2000;api.ingest(h,data(10,'100',null,null),now);assert.equal(api.series(h)[0].points[1].cpu,null);
now+=2000;api.ingest(h,data(10,'200'),now);assert.equal(api.series(h).length,2);assert.equal(api.series(h)[0].points.filter(Boolean).length,2);
now+=2000;api.ingest(h,{...data(),game_threads:{timeline_rows:[]}},now);assert.equal(api.series(h)[0].points.at(-1),null);
assert.equal(api.ingest(h,{...data(),generated_at:new Date(now-20000).toISOString()},now),false);
now+=2000;api.ingest(h,{...data(),game_pid:6},now);assert.equal(h.samples.length,1);
for(let i=0;i<100;i++){now+=2000;api.ingest(h,data(),now)}assert.ok(h.samples.length<=31);assert.ok(now-h.samples[0].at<=60000);
class Element{constructor(){this.children=[];this.textContent='';this.style={}}append(...x){this.children.push(...x)}replaceChildren(...x){this.children=x}}
const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id)};
class Clock extends Date{constructor(...a){super(...(a.length?a:[now]))}static now(){return now}}
const context={window:{document:{getElementById:get,createElement:()=>new Element()},renderProfileData:()=>{}},Date:Clock,setInterval:()=>0};
vm.runInNewContext(fs.readFileSync(require.resolve('../scripts/thread-timeline.js'),'utf8'),context);context.window.renderProfileData(data());now+=2000;context.window.renderProfileData(data());
assert.match(get('threadTimelineStatus').textContent,/Live.*1 threads/);assert.equal(get('threadTimeline').children[0].children[1].children[2].textContent,'80.0');assert.equal(get('threadTimeline').children[0].children[1].children[1].children[0].children.length,1);
console.log('PASS: live timeline duplicate/stale rejection, nulls, thread reuse, missing threads, restart reset, bounded history and rendering');
