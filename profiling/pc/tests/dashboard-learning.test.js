const assert=require('node:assert/strict');
const api=require('../scripts/dashboard-learning.js');
const d={game:'ACOrigins.exe',game_pid:10,container:'com.tencent.ig',backend:'DXVK',target_fps:60,generated_at:'2026-10-05T12:00:00Z',app_profile:{session:'one',fps:40,p95_ms:30},cpu:{game_ms_per_s:2000},gpu:{busy_percent:90},thermal:{cpu_c:80},memory:{available_mb:3000},surface:{p95_ms:35}};
assert.equal(api.sample(d).cpu,2);
assert.equal(api.sample({...d,app_profile:{}}).fps,null);
assert.notEqual(api.identity(d),api.identity({...d,game_pid:11}));
assert.notEqual(api.identity(d),api.identity({...d,app_profile:{...d.app_profile,session:'two'}}));
assert.notEqual(api.identity(d),api.identity({...d,target_fps:30}));
const a=api.sample(d),b=api.sample({...d,app_profile:{fps:null,p95_ms:null},gpu:{busy_percent:NaN}});
const s=api.summarize([a,b]);assert.equal(s.fps.mean,40);assert.equal(s.fps.count,1);assert.equal(s.gpu.count,1);assert.equal(s.cpu.mean,2);
assert.equal(api.summarize([]).fps.mean,null);
console.log('PASS: missing measurements excluded, core units, restart/session identity, sample counts');
// Exercise recording controls and DOM updates without a phone or screenshot.
const fs=require('node:fs'),vm=require('node:vm');
let now=Date.parse('2026-10-05T12:00:00Z');
class Clock extends Date{constructor(...args){super(...(args.length?args:[now]))}static now(){return now}}
class Element{constructor(){this.children=[];this.textContent='';this.value='';this.disabled=false}append(...x){this.children.push(...x)}replaceChildren(...x){this.children=x}click(){this.onclick?.()}}
const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id)};
const store=new Map(),document={getElementById:get,createElement:()=>new Element()};
const context={window:{document,localStorage:{getItem:k=>store.get(k),setItem:(k,v)=>store.set(k,v)},renderProfileData:()=>{}},Date:Clock,setTimeout:()=>1,setInterval:()=>1,clearTimeout:()=>{},URL:{},Blob:class{}};
vm.runInNewContext(fs.readFileSync(require.resolve('../scripts/dashboard-learning.js'),'utf8'),context);
function update(pid=10){context.window.renderProfileData({...d,generated_at:new Clock().toISOString(),game_pid:pid,process_family:[{pid:10,name:'game.exe',relation:'Selected game',state:'S',cpu_cores:1,rss_mb:100,ppid:1}]})}
update();get('pinBaseline').click();assert.match(get('comparisonStatus').textContent,/five fresh/);
for(let i=1;i<=6;i++){now+=1000;update();update()}get('pinBaseline').click();
let saved=JSON.parse(store.get('tyrantlator-comparisons-v1'));assert.equal(saved.A.samples.length,7);assert.equal(saved.A.duration,6);
now+=1000;update(11);assert.equal(JSON.parse(store.get('tyrantlator-comparisons-v1')).A.samples.length,7);
assert.match(get('comparisonResults').children[1].textContent,/1 samples/);
assert.equal(get('processFamily').children[0].children.length,2);
now+=20000;context.window.renderProfileData({...d,generated_at:new Clock(now-20000).toISOString()});assert.match(get('comparisonStatus').textContent,/unavailable/);
console.log('PASS: continuous live updates, baseline pinning, duplicate suppression, restart reset and stale rejection');
context.window.renderProfileData({...d,generated_at:new Clock().toISOString(),background_cpu:{status:'Live test',processes:[{pid:99,name:'helper.exe',state:'Z',relation:'Unconfirmed',cpu_cores:2}],alerts:[{pid:99,name:'helper.exe',title:'Exited main thread with active CPU',cpu_cores:2,seconds:6,detail:'Check purpose'}]}});
assert.equal(get('backgroundProcesses').children[0].children.length,2);
assert.match(get('backgroundAlerts').children[0].children[0].textContent,/helper.exe/);
console.log('PASS: live background table and alert rendering');
context.window.renderProfileData({...d,generated_at:new Clock().toISOString(),game_threads:{status:'Live test',total:2,measured:1,rows:[{tid:10,name:'dxvk-submit',role:'DXVK submission worker',cpu_ms_per_s:500,cpu_percent:50,cpu_cores:.5,state:'S',last_core:6,status:'Measured'},{tid:11,name:'new worker',role:'Unknown',cpu_ms_per_s:null,state:'R',last_core:2,status:'Warming up'}]}});
assert.equal(get('gameThreadRows').children[0].children.length,3);
assert.match(get('gameThreadStatus').textContent,/showing 2\/2/);
assert.equal(get('gameThreadRows').children[0].children[1].children[2].textContent,'50.0');
assert.equal(get('gameThreadRows').children[0].children[1].children[6].textContent,'C6');
console.log('PASS: live thread display, CPU units, partial samples and last-core label');
