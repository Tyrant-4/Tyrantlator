function Start-MonitorControl {
 $listener=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0)
 $listener.Start()
 $token=[guid]::NewGuid().ToString('N')
 [pscustomobject]@{listener=$listener;path=('/stop/'+$token);url=('http://127.0.0.1:'+$listener.LocalEndpoint.Port+'/stop/'+$token)}
}

function Receive-MonitorStop {
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
   $accepted=$request.StartsWith(('POST '+$Control.path+' HTTP/1.')) -and $request.EndsWith("`r`n`r`n")
   $status=if($accepted){'200 OK'}else{'404 Not Found'}
   $body=if($accepted){'{"ok":true}'}else{'{"ok":false}'}
   $response="HTTP/1.1 $status`r`nContent-Type: application/json`r`nAccess-Control-Allow-Origin: *`r`nCache-Control: no-store`r`nConnection: close`r`nContent-Length: $($body.Length)`r`n`r`n$body"
   $bytes=[Text.Encoding]::ASCII.GetBytes($response)
   $stream.Write($bytes,0,$bytes.Length)
   if($accepted){return $true}
  }catch{
   # An incomplete or disconnected request cannot stop the collector.
  }finally{$client.Close()}
 }
 return $false
}
