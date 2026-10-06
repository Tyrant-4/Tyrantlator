$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/monitor-control.ps1')
$control=Start-MonitorControl
try{
 if($control.listener.LocalEndpoint.Address.ToString() -ne '127.0.0.1'){throw 'Control escaped loopback'}
 foreach($case in @(@('GET',$control.path,$false),@('POST','/stop/wrong-session',$false),@('POST',$control.path,$true))){
  $client=New-Object Net.Sockets.TcpClient
  try{
   $client.Connect('127.0.0.1',$control.listener.LocalEndpoint.Port)
   $stream=$client.GetStream();$stream.ReadTimeout=1000
   $request="$($case[0]) $($case[1]) HTTP/1.1`r`nHost: 127.0.0.1`r`nOrigin: null`r`nContent-Length: 0`r`n`r`n"
   $bytes=[Text.Encoding]::ASCII.GetBytes($request);$stream.Write($bytes,0,$bytes.Length)
   $stop=Receive-MonitorStop $control
   if($stop -ne $case[2]){throw 'Wrong stop authorization result'}
   $reader=New-Object IO.StreamReader($stream);$response=$reader.ReadToEnd()
   $expected=if($case[2]){'200 OK'}else{'404 Not Found'}
   if(-not $response.Contains($expected) -or -not $response.Contains('Access-Control-Allow-Origin: *')){throw 'Bad control response'}
  }finally{$client.Close()}
 }
 if(Receive-MonitorStop $control){throw 'Empty queue requested stop'}
 'PASS: loopback-only control, POST-only session token, CORS response and nonblocking empty queue'
}finally{$control.listener.Stop()}
