const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {stopUrl}=require('../scripts/monitor-control.js');
const url='http://127.0.0.1:12345/stop/'+'a'.repeat(32);
assert.equal(stopUrl({monitoring:{stop_url:url}}),url);
for(const bad of ['https://example.com/stop','http://localhost:123/stop/'+'a'.repeat(32),url+'/extra'])assert.equal(stopUrl({monitoring:{stop_url:bad}}),null);
const button={disabled:true},message={},timers=[];let requests=0;
const context={document:{getElementById:id=>id==='stopMonitoring'?button:message},window:{renderProfileData(){}},Date,AbortController,setInterval:fn=>timers.push(fn),setTimeout,clearTimeout,fetch:async(u,opts)=>{assert.equal(u,url);assert.equal(opts.method,'POST');requests++;return {ok:true,json:async()=>({ok:true})}}};
vm.runInNewContext(fs.readFileSync(require.resolve('../scripts/monitor-control.js'),'utf8'),context);
const sample={session:'one',generated_at:new Date().toISOString(),monitoring:{collector_state:'running',stop_url:url}};
(async()=>{
 context.window.renderProfileData(sample);assert.equal(button.disabled,false);
 await button.onclick();assert.equal(requests,1);assert.equal(button.disabled,true);assert.equal(button.textContent,'Monitoring stopped');assert.match(message.textContent,/game and phone profiling exporter continue/);
 context.window.renderProfileData({...sample,session:'two',monitoring:{collector_state:'running',stop_url:url}});assert.equal(button.disabled,false);
 context.window.renderProfileData({...sample,generated_at:new Date(Date.now()-20000).toISOString(),monitoring:{collector_state:'running',stop_url:url}});assert.equal(button.disabled,true);
 console.log('PASS: session URL validation, stop action, stopped state, restart and stale disabling');
})().catch(e=>{console.error(e);process.exitCode=1});
