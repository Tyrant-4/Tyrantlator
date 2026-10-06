(function(){
 'use strict';
 function stopUrl(d){const u=d&&d.monitoring&&d.monitoring.stop_url;return typeof u==='string'&&/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}\/stop\/[a-f0-9]{32}$/.test(u)?u:null}
 if(typeof module!=='undefined')module.exports={stopUrl};
 if(typeof document==='undefined')return;
 const button=document.getElementById('stopMonitoring'),message=document.getElementById('monitorControlStatus');
 let current=null,pending=false,failure=null;
 function update(d){
  if(current&&current.session!==d.session)failure=null;
  current=d;const stopped=d.monitoring&&d.monitoring.collector_state==='stopped';
  button.disabled=pending||stopped||!stopUrl(d)||Date.now()-Date.parse(d.generated_at)>10000;
  button.textContent=pending?'Stopping…':stopped?'Monitoring stopped':'Stop monitoring';
  if(stopped)message.textContent='PC monitoring stopped. The game and phone profiling exporter continue. Reopen live.cmd to monitor again.';
  else if(!pending)message.textContent=failure||(stopUrl(d)?'Stops PC polling; your game keeps running. Phone profiling is controlled separately.':'Restart the PC collector to enable this button.');
 }
 const original=window.renderProfileData;
 window.renderProfileData=function(d){original(d);update(d)};
 if(window.profileData)update(window.profileData);
 setInterval(()=>{if(current&&!pending)update(current)},1000);
 button.onclick=async()=>{
  const url=stopUrl(current),session=current&&current.session;
  if(!url||button.disabled)return;
  failure=null;pending=true;update(current);message.textContent='Stopping PC monitoring…';
  const abort=new AbortController(),timeout=setTimeout(()=>abort.abort(),15000);
  try{
   const response=await fetch(url,{method:'POST',credentials:'omit',signal:abort.signal});
   const result=await response.json();if(!response.ok||result.ok!==true)throw new Error('Stop rejected');
   if(current.session===session){current.monitoring.collector_state='stopped';window.renderProfileData(current)}
  }catch{
   if(current.session===session&&current.monitoring.collector_state!=='stopped')failure='Could not confirm the stop. Check the collector window or try again.';
  }finally{
   clearTimeout(timeout);pending=false;
   update(current);
  }
 };
})();
