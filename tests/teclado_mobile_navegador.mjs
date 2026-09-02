import { chromium } from 'playwright';
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path';
const RAIZ='/home/user/mind-agent';
const T={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.svg':'image/svg+xml','.jpg':'image/jpeg','.mp4':'video/mp4'};
const s=http.createServer((q,r)=>{const u=decodeURIComponent(q.url.split('?')[0]);const p=path.join(RAIZ,u==='/'?'index.html':u);
  if(!p.startsWith(RAIZ)||!fs.existsSync(p)||fs.statSync(p).isDirectory()){r.writeHead(404);return r.end();}
  r.writeHead(200,{'Content-Type':T[path.extname(p)]||'application/octet-stream'});fs.createReadStream(p).pipe(r);});
await new Promise(r=>s.listen(4322,r));
const nav=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});

async function cena(w,h,rotulo){
  const ctx=await nav.newContext({viewport:{width:w,height:h},isMobile:true,hasTouch:true});
  const pg=await ctx.newPage();
  await pg.goto('http://localhost:4322/index.html'); await pg.waitForTimeout(1200);
  await pg.evaluate(()=>{document.getElementById('splash')?.remove();
    document.querySelectorAll('.vista').forEach(v=>v.classList.remove('ativa'));
    document.getElementById('vista-chat').classList.add('ativa');
    const m=document.getElementById('mensagens');
    const longa=document.createElement('div'); longa.className='bolha mind';
    longa.textContent='Mensagem muito longa. '.repeat(120);
    m.appendChild(longa);
    for(let i=0;i<20;i++){const d=document.createElement('div');d.className='bolha '+(i%2?'mind':'eu');
      d.textContent='Linha '+i+' da conversa com bastante texto para gerar rolagem de verdade.';m.appendChild(d);}
    m.scrollTop=m.scrollHeight;});
  await pg.waitForTimeout(300);
  const kb=async(k)=>{await pg.evaluate((k)=>{const vv=window.visualViewport;
    if(!window.__h)window.__h=vv.height;
    Object.defineProperty(vv,'height',{configurable:true,get:()=>window.__h-k});
    vv.dispatchEvent(new Event('resize'));},k); await pg.waitForTimeout(120);};
  const med=()=>pg.evaluate(()=>{const b=(el)=>{const r=el.getBoundingClientRect();return {top:+r.top.toFixed(1),bottom:+r.bottom.toFixed(1)};};
    const m=document.getElementById('mensagens');
    return {teclado:document.documentElement.dataset.teclado,
      topo:b(document.querySelector('#vista-chat .c-topo')),
      doca:b(document.querySelector('#vista-chat .doca')),
      distFundo:+(m.scrollHeight-m.scrollTop-m.clientHeight).toFixed(1),
      scrollY:window.scrollY, focado:document.activeElement?.id||null};});

  // foca o campo (como um toque real), abre teclado
  await pg.evaluate(()=>document.getElementById('campo-chat').focus());
  await kb(Math.round(h*0.42));
  const digitando=await med();
  // "envia": e o codigo desabilita SO o botao
  await pg.evaluate(()=>{document.querySelector('#form-chat .enviar').disabled=true;});
  await pg.waitForTimeout(80);
  const enviando=await med();
  await pg.evaluate(()=>{document.querySelector('#form-chat .enviar').disabled=false;});
  const depoisDoEnvio=await med();
  await kb(0);
  const fechado=await med();
  await ctx.close();
  return {rotulo,digitando,enviando,depoisDoEnvio,fechado};
}

const retrato=await cena(393,852,'iPhone 14 Pro retrato');
const paisagem=await cena(852,393,'iPhone 14 Pro paisagem');
const pequeno=await cena(375,667,'iPhone SE');
console.log(JSON.stringify([retrato,paisagem,pequeno],null,1));
await nav.close(); s.close();
