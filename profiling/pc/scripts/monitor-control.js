(function(){
 'use strict';
 function actionUrl(d,action){const u=d&&d.monitoring&&d.monitoring[action+'_url'];return typeof u==='string'&&new RegExp('^http://127\\.0\\.0\\.1:[1-9]\\d{0,4}/'+action+'/[a-f0-9]{32}$').test(u)?u:null}
 function stopUrl(d){return actionUrl(d,'stop')}
 if(typeof module!=='undefined')module.exports={stopUrl,actionUrl};
 if(typeof document==='undefined')return;
 const button=document.getElementById('stopMonitoring'),message=document.getElementById('monitorControlStatus');
 let current=null,pending=null,failure=null;
 function update(d){
  if(current&&current.session!==d.session)failure=null;
  current=d;const stopped=d.monitoring&&d.monitoring.collector_state==='stopped';
  const action=stopped?'resume':'stop',stamp=stopped?d.monitoring.control_updated_at:d.generated_at;
  button.disabled=!!pending||!actionUrl(d,action)||(stopped&&!d.monitoring.can_resume)||!Number.isFinite(Date.parse(stamp))||Date.now()-Date.parse(stamp)>10000;
  button.textContent=pending==='resume'?'Resuming…':pending?'Stopping…':stopped?'Resume monitoring':'Stop monitoring';
  if(stopped&&!pending)message.textContent=failure||'PC monitoring stopped. The game and phone profiling exporter continue. Resume restores the same monitoring options.';
  else if(!pending)message.textContent=failure||(stopUrl(d)?'Stops PC polling; your game keeps running. Phone profiling is controlled separately.':'Restart the PC collector to enable this button.');
 }
 const original=window.renderProfileData;
 window.renderProfileData=function(d){original(d);update(d)};
 if(window.profileData)update(window.profileData);
 setInterval(()=>{if(current&&!pending)update(current)},1000);
 button.onclick=async()=>{
  const action=current&&current.monitoring.collector_state==='stopped'?'resume':'stop';
  const url=actionUrl(current,action),session=current&&current.session;
  if(!url||button.disabled)return;
  failure=null;pending=action;update(current);message.textContent=action==='resume'?'Resuming PC monitoring…':'Stopping PC monitoring…';
  const abort=new AbortController(),timeout=setTimeout(()=>abort.abort(),15000);
  try{
   const response=await fetch(url,{method:'POST',credentials:'omit',signal:abort.signal});
   const result=await response.json();if(!response.ok||result.ok!==true)throw new Error('Stop rejected');
   if(current.session===session){
    current.monitoring.collector_state=action==='stop'?'stopped':'running';
    current.monitoring.control_updated_at=new Date().toISOString();
    window.renderProfileData(current)
   }
  }catch{
   if(current.session===session)failure='Could not confirm '+action+'. Check the collector window or try again.';
  }finally{
   clearTimeout(timeout);pending=null;
   update(current);
  }
 };
})();
