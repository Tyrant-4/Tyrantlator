(function(scope){
 'use strict';
 const number=x=>x!==null&&x!==undefined&&x!==''&&Number.isFinite(Number(x))?Number(x):null;
 const metrics=[
  {key:'fps',label:'App FPS',unit:'FPS',absolute:10,relative:.2,value:d=>d.app_profile?.fps,element:'hudFps'},
  {key:'appP95',label:'App present p95',unit:'ms',absolute:5,relative:.35,value:d=>d.app_profile?.p95_ms,element:'hudP95'},
  {key:'surfaceP95',label:'Compositor p95',unit:'ms',absolute:8,relative:.5,value:d=>d.surface?.p95_ms,element:'p95'},
  {key:'gpu',label:'GPU busy',unit:'%',absolute:20,relative:0,value:d=>d.gpu?.busy_percent,element:'gpu'},
  {key:'cpu',label:'Game CPU',unit:'cores',absolute:1,relative:.3,value:d=>number(d.cpu?.game_ms_per_s)===null?null:d.cpu.game_ms_per_s/1000,element:'cpu'},
  {key:'ram',label:'Available RAM',unit:'MB',absolute:512,relative:.15,value:d=>d.memory?.available_mb,element:'memory'},
  {key:'temp',label:'CPU temperature',unit:'°C',absolute:3,relative:0,value:d=>d.thermal?.cpu_c,stamp:d=>d.sampling?.thermal_at},
  {key:'gpuTemp',label:'GPU temperature',unit:'°C',absolute:3,relative:0,value:d=>d.thermal?.gpu_c,stamp:d=>d.sampling?.thermal_at},
  {key:'shader',label:'DXVK shader-worker CPU',unit:'cores',absolute:.5,relative:.75,value:d=>d.graphics_workers?.shader?.cpu_cores},
  {key:'queue',label:'Busiest thread CPU queue',unit:'ms/s',absolute:100,relative:1,value:d=>d.game_threads?.queue_rows?.[0]?.cpu_queue_ms_per_s},
  {key:'jit',label:'FEX JIT work in sample',unit:'ms',absolute:10,relative:1,value:d=>d.jit?.new_ms},
  {key:'frequency',label:'CPU allowed-limit drop',unit:'%',absolute:8,relative:0,value:d=>d.cpu?.policy_drop_percent},
  {key:'swap',label:'Phone swap-in',unit:'pages/s',absolute:256,relative:1,value:d=>d.memory?.swap_in_pages_per_s},
  {key:'ioWait',label:'Phone CPU I/O wait',unit:'%',absolute:2,relative:0,value:d=>d.storage?.io_wait_percent,stamp:d=>d.storage?.sampled_at},
  {key:'pageIn',label:'Phone paging in',unit:'MiB/s',absolute:20,relative:1,value:d=>d.storage?.phone_page_in_mib_s,stamp:d=>d.storage?.sampled_at},
  {key:'faults',label:'Game major page faults',unit:'/s',absolute:100,relative:1,value:d=>d.storage?.game_major_faults_s,stamp:d=>d.storage?.sampled_at}
 ];
 const median=values=>{const sorted=values.slice().sort((a,b)=>a-b),i=Math.floor(sorted.length/2);return sorted.length%2?sorted[i]:(sorted[i-1]+sorted[i])/2};
 function identity(d){return [d.session,d.game,d.game_pid,d.container,d.backend,d.target_fps,d.app_profile?.session||''].join('|')}
 function create(){
  let key=null,gameKey=null,lastAt=0,baselines=new Map(),events=[],unread=0,sequence=0,mode='waiting';
  function reset(){baselines.clear();lastAt=0}
  return {
   accept(d,now=Date.now()){
    const at=Date.parse(d?.generated_at),nextKey=d?identity(d):null;
    if(nextKey!==key){key=nextKey;reset();const nextGame=[d?.game,d?.game_pid,d?.container].join('|');if(nextGame!==gameKey){gameKey=nextGame;events=[];unread=0}}
    if(d?.monitoring?.collector_state==='stopped'){mode='stopped';reset();return []}
    if(!Number.isFinite(at)||at>now+5000||now-at>10000||!d?.game||d.game==='Unavailable'){mode='waiting';reset();return []}
    if(at<=lastAt)return [];
    if(lastAt&&at-lastAt>15000)reset();
    lastAt=at;mode='live';const added=[];
    for(const metric of metrics){
     const value=number(metric.value(d)),stamp=Date.parse(metric.stamp?metric.stamp(d):d.generated_at);
     if(value===null||!Number.isFinite(stamp)||stamp>now+5000||now-stamp>15000){baselines.delete(metric.key);continue}
     let b=baselines.get(metric.key);
     if(!b||stamp-b.at>15000||stamp<b.at){b={at:0,points:[],direction:0};baselines.set(metric.key,b)}
     if(stamp===b.at)continue;
     b.points=b.points.filter(p=>stamp-p.at<=30000);const old=b.points.length>=3&&stamp-b.points[0].at>=5000?median(b.points.map(p=>p.value)):null;
     if(old!==null){
      const delta=value-old,large=Math.abs(delta)>=metric.absolute&&Math.abs(delta)>=Math.abs(old)*metric.relative,direction=large?Math.sign(delta):0;
      const further=direction===b.direction&&Math.sign(value-b.alertValue)===direction&&Math.abs(value-b.alertValue)>=Math.max(metric.absolute,Math.abs(b.alertValue)*metric.relative);
      if(direction&&(direction!==b.direction||further)){
       const event={id:++sequence,key:metric.key,label:metric.label,unit:metric.unit,at:stamp,before:old,after:value,delta,window_s:(stamp-b.points[0].at)/1000,element:metric.element};added.push(event);events.push(event);unread++;b.alertValue=value;
      }
      b.direction=direction;
     }
     b.points.push({at:stamp,value});if(b.points.length>60)b.points.shift();b.at=stamp;
    }
    if(events.length>40)events=events.slice(-40);unread=Math.min(unread,events.length);
    return added;
   },
   acknowledge(){unread=0},
   get events(){return events.slice()},get unread(){return unread},get mode(){return mode},get ready(){return [...baselines.values()].some(b=>b.points.length>=3&&b.at-b.points[0].at>=5000)}
  };
 }
 const api={create,metrics};if(typeof module!=='undefined')module.exports=api;
 if(!scope.document)return;
 const doc=scope.document,$=id=>doc.getElementById(id),detector=create();let current=null,audio=null,sound=false,revision=0;
 const format=(value,unit)=>`${value.toFixed(unit==='MB'||unit==='pages/s'?0:1)} ${unit}`;
 function paint(){
  const badge=$('changeBadge'),count=detector.unread;
  badge.textContent=count?`${count} new change${count===1?'':'s'}`:detector.mode==='stopped'?'Change alerts · paused':detector.mode!=='live'?'Change alerts · waiting':detector.ready?'Change alerts · watching':'Change alerts · warming up';
  badge.className=count?'change-badge has-changes':'change-badge';$('ackChanges').disabled=!count;
  const toast=$('changeToast'),last=detector.events.at(-1);toast.hidden=!count;if(count&&last)toast.textContent=`${count} new change${count===1?'':'s'} · ${last.label}: ${format(last.before,last.unit)} → ${format(last.after,last.unit)} · ${new Date(last.at).toLocaleTimeString()}`;
  for(const metric of metrics){if(metric.element){const el=$(metric.element);const last=detector.events.findLast(e=>e.key===metric.key);const active=last&&Date.now()-last.at<15000;el.setAttribute('data-sudden-change',active?'true':'false');el.setAttribute('title',active?`Recent ${format(last.before,last.unit)} → ${format(last.after,last.unit)}`:'')}}
  const draw=()=>{
   $('changeAlertStatus').textContent=detector.mode==='stopped'?'Monitoring stopped · change history frozen.':detector.mode!=='live'?'Waiting for fresh game data.':detector.ready?'Watching for sudden changes · recent median versus newest reading.':'Warming up · needs three readings spanning five seconds.';
   const root=$('changeEvents');root.replaceChildren();const events=detector.events.slice().reverse();
   if(!events.length){root.className='deep-scroll empty';root.textContent='No sudden changes detected yet.';return}
   root.className='deep-scroll';const table=doc.createElement('table');table.className='deep-table';const head=doc.createElement('tr');
   for(const label of ['Parameter','Time','Recent → now','Change','Baseline window']){const cell=doc.createElement('th');cell.textContent=label;head.append(cell)}table.append(head);
   for(const e of events){const row=doc.createElement('tr');for(const text of [e.label,new Date(e.at).toLocaleTimeString(),`${format(e.before,e.unit)} → ${format(e.after,e.unit)}`,`${e.delta>=0?'+':''}${e.delta.toFixed(1)} ${e.unit==='%'?'points':e.unit}`,`${e.window_s.toFixed(0)} s`]){const cell=doc.createElement('td');cell.textContent=text;row.append(cell)}table.append(row)}root.append(table);
  };
  scope.TyrantDashboardRender.offer('overview','change-alerts',current,draw,`${revision}|${detector.mode}|${detector.ready}`);
 }
 function beep(){if(!sound||!audio||audio.state!=='running')return;try{const tone=audio.createOscillator(),gain=audio.createGain(),at=audio.currentTime;tone.frequency.setValueAtTime(880,at);gain.gain.setValueAtTime(.025,at);gain.gain.exponentialRampToValueAtTime(.001,at+.14);tone.connect(gain);gain.connect(audio.destination);tone.onended=()=>{tone.disconnect();gain.disconnect()};tone.start(at);tone.stop(at+.15)}catch{sound=false;$('changeSound').textContent='Sound: unavailable';$('changeSound').setAttribute('aria-pressed','false')}}
 $('changeSound').onclick=async()=>{
  if(sound){sound=false;$('changeSound').textContent='Sound: off';$('changeSound').setAttribute('aria-pressed','false');try{await audio.suspend()}catch{}return}
  try{const Audio=scope.AudioContext||scope.webkitAudioContext;if(!Audio)throw new Error('Audio unavailable');audio=audio||new Audio();await audio.resume();if(audio.state!=='running')throw new Error('Audio suspended');sound=true;$('changeSound').textContent='Sound: on';$('changeSound').setAttribute('aria-pressed','true')}catch{$('changeSound').textContent='Sound: unavailable';sound=false}
 };
 $('ackChanges').onclick=()=>{detector.acknowledge();revision++;paint()};
 $('changeBadge').onclick=()=>{$('tab-overview').click();$('changePanel').scrollIntoView?.({behavior:'smooth',block:'start'})};
 $('changeToast').onclick=$('changeBadge').onclick;
 const original=scope.renderProfileData;
 scope.renderProfileData=d=>{original(d);current=d;const added=detector.accept(d);if(added.length){revision++;beep()}paint()};
 setInterval(()=>{if(current){detector.accept(current);paint()}},2000);
 if(scope.profileData)scope.renderProfileData(scope.profileData);
})(typeof window==='undefined'?globalThis:window);
