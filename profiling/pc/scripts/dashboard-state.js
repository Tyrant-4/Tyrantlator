(function(scope){
 'use strict';
 function state(d,now=Date.now()){
  if(!d)return 'waiting';
  if(d.monitoring?.collector_state==='stopped')return 'stopped';
  const at=Date.parse(d.generated_at);
  return Number.isFinite(at)&&at<=now+5000&&now-at<=10000?'live':'stale';
 }
 function label(d,now=Date.now()){
  const s=state(d,now);
  if(s==='waiting')return 'Waiting for monitoring';
  if(s==='stopped')return 'Stopped · readings frozen';
  if(s==='live')return 'Live · updating';
  const age=now-Date.parse(d.generated_at);
  return Number.isFinite(age)&&age>=0?'Disconnected · last sample '+Math.round(age/1000)+'s ago':'No fresh readings';
 }
 const api={state,label,isLive:(d,now)=>state(d,now)==='live'};
 scope.TyrantDashboardState=api;
 if(typeof module!=='undefined')module.exports=api;
})(typeof window==='undefined'?globalThis:window);
