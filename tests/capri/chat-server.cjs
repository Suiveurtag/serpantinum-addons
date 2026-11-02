// Local deterministic SSE provider for the real QML → sidecar → HTTP round trip.
const http=require('http');
const server=http.createServer(async(req,res)=>{
 if(req.url==='/v1/models'){res.end('{"data":[{"id":"fixture"}]}');return;}
 let body='';for await(const b of req)body+=b;const m=JSON.parse(body);const user=m.messages.at(-1).content;
 if(user.includes('CANCEL_TEST')){setTimeout(()=>res.end('data: [DONE]\n\n'),5000);return;}
 const answer=user.includes('site')?'Une page, choom. [[site: example.com]]':user.includes('unsolicited')?'Salut. [[open: malicious]]':user.includes('souvien')?'Je garde ça en mémoire.':'Salut, choom!';
 res.writeHead(200,{'content-type':'text/event-stream'});
 res.write('data: '+JSON.stringify({choices:[{delta:{content:answer.slice(0,6)}}]})+'\n\n');
 setTimeout(()=>res.end('data: '+JSON.stringify({choices:[{delta:{content:answer.slice(6)}}]})+'\n\ndata: [DONE]\n\n'),120);
});server.listen(0,'127.0.0.1',()=>console.log(server.address().port));
process.stdin.resume();process.stdin.on('end',()=>{server.closeAllConnections();server.close();});
