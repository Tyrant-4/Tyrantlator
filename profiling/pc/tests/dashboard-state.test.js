const assert=require('node:assert/strict'),state=require('../scripts/dashboard-state.js');
const now=Date.now(),d={generated_at:new Date(now).toISOString()};
assert.equal(state.state(null,now),'waiting');assert.equal(state.state(d,now),'live');
assert.equal(state.state({...d,monitoring:{collector_state:'stopped'}},now),'stopped');
assert.equal(state.isLive({...d,monitoring:{collector_state:'stopped'}},now),false);
assert.equal(state.state(d,now+11000),'stale');
for(const at of ['invalid',new Date(now+10000).toISOString()])assert.equal(state.isLive({generated_at:at},now),false);
assert.match(state.label({...d,monitoring:{collector_state:'stopped'}},now),/frozen/);
console.log('PASS: live, stopped, disconnected, invalid and future timestamps');
