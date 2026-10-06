function Start-MonitorControl {
 $listener=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0)
 $listener.Start()
 $token=[guid]::NewGuid().ToString('N')
 $base='http://127.0.0.1:'+$listener.LocalEndpoint.Port
 [pscustomobject]@{listener=$listener;path=('/stop/'+$token);resumePath=('/resume/'+$token);url=($base+'/stop/'+$token);resumeUrl=($base+'/resume/'+$token)}
}

function Receive-MonitorCommand {
 param($Control)
 # Check only already-queued connections; never wait for a dashboard client.
 for($i=0;$i -lt 4 -and $Control.listener.Pending();$i++){
  $client=$Control.listener.AcceptTcpClient()
  try{
   $stream=$client.GetStream();$stream.ReadTimeout=250;$stream.WriteTimeout=250
   $header=New-Object System.Text.StringBuilder
   while($header.Length -lt 4096){
    $byte=$stream.ReadByte()
    if($byte -lt 0){break}
    [void]$header.Append([char]$byte)
    if($header.ToString().EndsWith("`r`n`r`n")){break}
   }
   $request=$header.ToString()
   $action=$null
   if($request.EndsWith("`r`n`r`n")){
    if($request.StartsWith(('POST '+$Control.path+' HTTP/1.'))){$action='stop'}
    elseif($request.StartsWith(('POST '+$Control.resumePath+' HTTP/1.'))){$action='resume'}
   }
   $accepted=$null -ne $action
   $status=if($accepted){'200 OK'}else{'404 Not Found'}
   $body=if($accepted){'{"ok":true}'}else{'{"ok":false}'}
   $response="HTTP/1.1 $status`r`nContent-Type: application/json`r`nAccess-Control-Allow-Origin: *`r`nCache-Control: no-store`r`nConnection: close`r`nContent-Length: $($body.Length)`r`n`r`n$body"
   $bytes=[Text.Encoding]::ASCII.GetBytes($response)
   $stream.Write($bytes,0,$bytes.Length)
   if($accepted){return $action}
  }catch{
   # An incomplete or disconnected request cannot stop the collector.
  }finally{$client.Close()}
 }
 return $null
}

function Write-MonitorSnapshot {
 param($Snapshot,[string]$Path)
 $json=$Snapshot | ConvertTo-Json -Depth 8 -Compress
 [IO.File]::WriteAllText($Path,('window.profileData='+$json+';if(window.renderProfileData){window.renderProfileData(window.profileData);}'),(New-Object Text.UTF8Encoding($false)))
}
