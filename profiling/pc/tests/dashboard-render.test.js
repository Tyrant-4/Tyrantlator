const assert=require('node:assert/strict'),{create}=require('../scripts/dashboard-render.js');
const r=create(),d={session:'one',generated_at:'one'};let overview=0,cpu=0,latest=0,ingested=0;
r.offer('overview','metrics',d,()=>overview++);assert.equal(overview,1);
r.offer('overview','metrics',d,()=>overview++);assert.equal(overview,1);
for(let i=0;i<10;i++){ingested++;r.offer('cpu','threads',{...d,generated_at:String(i)},()=>{cpu++;latest=i})}
assert.equal(ingested,10);assert.equal(cpu,0);
r.activate('cpu');assert.equal(cpu,1);assert.equal(latest,9);
r.offer('cpu','threads',{...d,generated_at:'9'},()=>cpu++);assert.equal(cpu,1);
r.resize();assert.equal(cpu,2);assert.equal(overview,1);
r.offer('processes','inventory',d,()=>latest++,'source-one');r.activate('processes');const old=latest;
r.offer('processes','inventory',{...d,generated_at:'new-fast-sample'},()=>latest++,'source-one');assert.equal(latest,old);
r.offer('processes','inventory',d,()=>latest++,'source-two');assert.equal(latest,old+1);
console.log('PASS: active-only rendering, unchanged data suppression, latest hidden data and resize');
