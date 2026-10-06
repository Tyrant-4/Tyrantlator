(function(){
 'use strict';
 if(typeof document==='undefined')return;
 const tabs=[...document.querySelectorAll('[role="tab"]')];
 function select(tab,focus=false){
  for(const item of tabs){const selected=item===tab;item.setAttribute('aria-selected',String(selected));item.tabIndex=selected?0:-1;document.getElementById(item.getAttribute('aria-controls')).hidden=!selected}
  if(focus)tab.focus();
  try{localStorage.setItem('tyrantlator-profiler-tab',tab.id)}catch{}
  window.dispatchEvent(new Event('resize'));
 }
 for(const [index,tab] of tabs.entries()){
  tab.onclick=()=>select(tab);
  tab.onkeydown=e=>{
   let next;
   if(e.key==='ArrowRight')next=(index+1)%tabs.length;
   else if(e.key==='ArrowLeft')next=(index+tabs.length-1)%tabs.length;
   else if(e.key==='Home')next=0;
   else if(e.key==='End')next=tabs.length-1;
   else return;
   e.preventDefault();select(tabs[next],true);
  };
 }
 let saved;try{saved=localStorage.getItem('tyrantlator-profiler-tab')}catch{}
 if(tabs.length)select(tabs.find(t=>t.id===saved)||tabs[0]);
})();
