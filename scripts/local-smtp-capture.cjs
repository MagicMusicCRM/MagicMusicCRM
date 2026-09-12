const net=require('node:net'),assert=require('node:assert/strict');
async function startLocalSmtpCapture(){
 const messages=[],sockets=new Set();
 const server=net.createServer(socket=>{sockets.add(socket);let buffer='',dataMode=false,body=[],recipient='';socket.setEncoding('utf8');socket.write('220 local-audit SMTP ready\r\n');socket.on('error',()=>{});socket.on('close',()=>sockets.delete(socket));
  socket.on('data',chunk=>{buffer+=chunk;while(buffer.includes('\r\n')){const end=buffer.indexOf('\r\n'),line=buffer.slice(0,end);buffer=buffer.slice(end+2);
   if(dataMode){if(line==='.'){messages.push({recipient,body:body.join('\r\n'),receivedAt:Date.now()});body=[];dataMode=false;socket.write('250 local message accepted\r\n');}else body.push(line.startsWith('..')?line.slice(1):line);continue;}
   if(/^EHLO|^HELO/.test(line))socket.write('250 local-audit\r\n');
   else if(line.startsWith('MAIL FROM:'))socket.write('250 sender accepted\r\n');
   else if(line.startsWith('RCPT TO:')){recipient=line.match(/<([^>]+)>/)?.[1]??'';if(!recipient.endsWith('@example.test')){socket.end('550 synthetic recipients only\r\n');return;}socket.write('250 recipient accepted\r\n');}
   else if(line==='DATA'){dataMode=true;socket.write('354 finish with dot\r\n');}
   else if(line==='QUIT'){socket.end('221 closing\r\n');}
   else socket.write('502 unsupported\r\n');
  }});
 });
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
 return {port:server.address().port,messages,async waitFor(recipient,after=0){const deadline=Date.now()+12000;while(Date.now()<deadline){const found=messages.slice(after).find(m=>m.recipient===recipient);if(found)return found;await new Promise(r=>setTimeout(r,100));}throw Error('No synthetic SMTP delivery within 12 seconds');},async close(){for(const socket of sockets)socket.destroy();await new Promise(resolve=>server.close(resolve));}};
}
module.exports={startLocalSmtpCapture};
