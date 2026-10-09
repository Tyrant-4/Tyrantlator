WITH
b AS (SELECT start_ts, end_ts, (end_ts-start_ts)/1e9 AS seconds FROM trace_bounds),
cpu AS (
 SELECT t.upid, s.utid,
 SUM(MAX(0,MIN(CASE WHEN s.dur<0 THEN b.end_ts ELSE s.ts+s.dur END,b.end_ts)-MAX(s.ts,b.start_ts)))/1e6 AS cpu_ms
 FROM sched s JOIN thread t USING(utid) CROSS JOIN b
 WHERE s.ts<b.end_ts AND (s.dur<0 OR s.ts+s.dur>b.start_ts) AND t.upid IS NOT NULL
 GROUP BY s.utid
),
game AS (
 SELECT p.upid,p.pid,p.name,SUM(c.cpu_ms) AS cpu_ms
 FROM process p JOIN cpu c USING(upid)
 WHERE lower(substr(p.name,-length('GAME_NAME')))=lower('GAME_NAME')
 GROUP BY p.upid ORDER BY cpu_ms DESC LIMIT 1
),
ready AS (
 SELECT st.utid,MAX(0,MIN(CASE WHEN st.dur<0 THEN b.end_ts ELSE st.ts+st.dur END,b.end_ts)-MAX(st.ts,b.start_ts))/1e6 AS ms
 FROM thread_state st JOIN thread t USING(utid) JOIN game g USING(upid) CROSS JOIN b
 WHERE st.state IN ('R','R+') AND st.dur>0 AND st.ts<b.end_ts AND st.ts+st.dur>b.start_ts
),
ranked AS (SELECT *,ROW_NUMBER() OVER(PARTITION BY utid ORDER BY ms) AS rn,COUNT(*) OVER(PARTITION BY utid) AS n FROM ready),
waits AS (
 SELECT utid,SUM(ms) AS runnable_ms,MAX(ms) AS max_wait_ms,
 MAX(CASE WHEN rn=CAST(n*0.95+0.999999 AS INT) THEN ms END) AS p95_wait_ms FROM ranked GROUP BY utid
),
hot AS (
 SELECT t.tid,COALESCE(t.name,'Unnamed thread') AS name,c.cpu_ms,
 ROUND(c.cpu_ms/(b.seconds*10),2) AS cpu_percent,
 COALESCE(w.runnable_ms,0) AS runnable_ms,COALESCE(w.p95_wait_ms,0) AS p95_wait_ms,COALESCE(w.max_wait_ms,0) AS max_wait_ms
 FROM cpu c JOIN thread t USING(utid) JOIN game g USING(upid) LEFT JOIN waits w USING(utid) CROSS JOIN b
 ORDER BY c.cpu_ms DESC LIMIT 12
),
others AS (
 SELECT p.pid,p.name,SUM(c.cpu_ms) AS cpu_ms,ROUND(SUM(c.cpu_ms)/(b.seconds*1000),2) AS cpu_cores
 FROM cpu c JOIN process p USING(upid) CROSS JOIN b
 WHERE p.pid!=0 AND p.upid NOT IN (SELECT upid FROM game)
 GROUP BY p.upid ORDER BY cpu_ms DESC LIMIT 8
)
SELECT json_object(
 'duration_s',(SELECT seconds FROM b),
 'scheduler_slices',(SELECT COUNT(*) FROM sched),
 'runnable_slices',(SELECT COUNT(*) FROM thread_state WHERE state IN ('R','R+')),
 'unfinished_game_waits',(SELECT COUNT(*) FROM thread_state st JOIN thread t USING(utid) JOIN game g USING(upid) WHERE st.state IN ('R','R+') AND st.dur<0),
 'data_loss_events',(SELECT COALESCE(SUM(value),0) FROM stats WHERE severity='data_loss' AND value>0),
 'game',(SELECT json_object('pid',pid,'name',name,'cpu_ms',ROUND(cpu_ms,2),'cpu_cores',ROUND(cpu_ms/(b.seconds*1000),2)) FROM game CROSS JOIN b),
 'threads',json((SELECT json_group_array(json_object('tid',tid,'name',name,'cpu_ms',ROUND(cpu_ms,2),'cpu_percent',cpu_percent,'runnable_ms',ROUND(runnable_ms,2),'p95_wait_ms',ROUND(p95_wait_ms,2),'max_wait_ms',ROUND(max_wait_ms,2))) FROM hot)),
 'competing_processes',json((SELECT json_group_array(json_object('pid',pid,'name',name,'cpu_ms',ROUND(cpu_ms,2),'cpu_cores',cpu_cores)) FROM others))
) AS deep_profile_json;
