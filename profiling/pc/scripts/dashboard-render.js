(function(scope){
 'use strict';
 function create(){
  const jobs=new Map();let active='overview';
  function paint(job,force=false){if(job.view===active&&(force||job.revision!==job.painted)){job.render();job.painted=job.revision}}
  return {
   offer(view,key,data,render,revision){
    const id=view+'/'+key,prior=jobs.get(id);
    const stamp=revision??[data?.session,data?.generated_at,data?.monitoring?.collector_state,scope.TyrantDashboardState?.state(data)].join('|');
    const job={view,render,revision:stamp,painted:prior?.painted};jobs.set(id,job);paint(job);
   },
   activate(view){active=view;for(const job of jobs.values())paint(job,true)},
   resize(){for(const job of jobs.values())paint(job,true)},
   get active(){return active}
  };
 }
 if(typeof module!=='undefined')module.exports={create};
 scope.TyrantDashboardRender=create();
})(typeof window==='undefined'?globalThis:window);
