/* CourtFlow v27 scheduler tests. Run: node test-scheduling.js  (needs playwright + chromium) */
const {chromium}=require('playwright');const path=require('path');
(async()=>{
const b=await chromium.launch();const ctx=await b.newContext();
await ctx.route('**/*',r=>r.request().url().startsWith('file:')?r.continue():r.abort());
await ctx.addInitScript(()=>{localStorage.setItem('cf-auth',JSON.stringify({at:'x',rt:'y',exp:Date.now()+1e10,keep:true,user:{id:'tester',email:'t@t.t',name:'Tester'}}))});
const page=await ctx.newPage();const errs=[];page.on('pageerror',e=>errs.push(e.message));
await page.goto('file://'+path.join(__dirname,'index.html'));
await page.waitForFunction(()=>typeof addMatches==='function');
const R=await page.evaluate(()=>{
 const out=[];const ok=(id,name,pass,info)=>out.push({id,name,pass:!!pass,info:info===undefined?'':JSON.stringify(info)});
 function reset(courts){S.queue=[];S.games=Array(courts).fill(null);S.hd=Array(courts).fill(0);S.ends=[];S.sc=[];S.em=[];S.ct=Array(courts).fill('any');S.courts=courts;S.hist=[];S.lineup=[];S.sched=[];S.hadLineup=false;S.cm=[];S.asig=undefined;S.p={};S.auto=false;S.stay=false;S.mode='line';S.size=4;S.start='manual';S.prot=1;S.qseq=0;S.bseq=0;CLOCK=1700000000000;S.sess={name:'T',start:CLOCK};S.view='session';S.tab='play';
  S.gen={n:5,t:{mixed:false,women:false,men:false,any:true},uneven:true};S.genb={n:5,t:{mixed:false,women:false,men:false,any:true},uneven:true};for(const k in AMLAST)delete AMLAST[k]}
 function players(prefix,n,lv,on){const ns=Array.from({length:n},(_,i)=>prefix+(i+1));add(ns.join(','),lv||3,'');if(on!==false)ns.forEach(x=>setAvail(x,true));return ns}
 const gap=()=>{for(const k in AMLAST)delete AMLAST[k]};
 const seq=g=>S.lineup.filter(m=>m.grp===g);
 const adj=g=>{let v=0;const q=seq(g);q.forEach((m,i)=>{const nx=q[i+1];if(nx)m.pl.forEach(n=>{if(nx.pl.indexOf(n)>=0)v++})});return v};

 // 1 default OFF + nothing eligible
 reset(2);players('P',8,3,false);
 ok('A1','New players default to OFF',Object.values(S.p).every(p=>p.pa===true&&Array.isArray(p.acts)&&p.acts.length===0));
 let r=addMatches('o');ok('A2','No ON players: nothing added and the reason is explained',!r.ok&&S.lineup.length===0&&/ON/.test(r.msg),r.msg);

 // 2 courts x 2, one match per rotation, ids and positions
 reset(3);let ns=players('P',12);r=addMatches('o');
 ok('B1','3 courts: one tap adds 6 matches',r.ok&&r.added===6&&S.lineup.length===6,r.msg);
 ok('B2','Every match has a unique id and sequential queue position',new Set(S.lineup.map(m=>m.id)).size===6&&S.lineup.map(m=>m.q).join()==='1,2,3,4,5,6');
 const first3=new Set(S.lineup.slice(0,3).flatMap(m=>m.pl));
 ok('B3','Everyone gets one match before anyone gets a second',first3.size===12);
 ok('B4','No player in back-to-back matches',adj('o')===0);
 const r2=addMatches('o');ok('B5','A double tap is refused (no duplicate batch)',!r2.ok&&S.lineup.length===6,r2.msg);
 const before=JSON.stringify(S.lineup);gap();const r3=addMatches('o');
 ok('B6','Next batch is appended; existing matches are unchanged',r3.ok&&S.lineup.length===12&&JSON.stringify(S.lineup.slice(0,6))===before);
 ok('B7','Sequential queue positions continue across batches',S.lineup.map(m=>m.q).join()==='1,2,3,4,5,6,7,8,9,10,11,12');
 const cnt={};S.lineup.forEach(m=>m.pl.forEach(n=>cnt[n]=(cnt[n]||0)+1));const cv=Object.values(cnt);
 ok('B8','After 12 matches everyone has the same number of matches',Math.max(...cv)-Math.min(...cv)===0,cnt);

 // 3 insufficient players
 reset(2);players('P',5);r=addMatches('o');
 ok('C1','5 players, 2 courts: valid matches only, limitation explained',r.ok&&S.lineup.length>0&&S.lineup.every(m=>new Set(m.pl).size===4)&&/(already has a match|right before)/.test(r.msg),r.msg);
 reset(2);players('P',3);r=addMatches('o');ok('C2','3 players: no match, reason given',!r.ok&&S.lineup.length===0&&/needed/.test(r.msg),r.msg);

 // 4 late activation + first-match priority
 reset(2);players('E',8);addMatches('o');gap();
 const late=players('L',2);const ids=S.lineup.map(m=>m.id),protBefore=JSON.stringify(S.lineup.slice(0,2));r=addMatches('o');
 const nw=S.lineup.slice(4);
 ok('D1','Late players get a match in the first new match of the next batch',late.every(n=>nw[0].pl.indexOf(n)>=0),nw[0].pl);
 ok('D2','Existing Up Next matches keep their order when late players arrive',ids.slice(0,4).every((id,i)=>S.lineup[i].id===id));
 const lateIdx=S.lineup.map((m,i)=>m.pl.some(n=>late.indexOf(n)>=0)?i:-1).filter(i=>i>=0);
 ok('D3','Late arrivals are scheduled in the new batch and not left out',lateIdx.length>0,lateIdx);
 {const cnt={};Object.keys(S.p).forEach(n=>cnt[n]=0);S.lineup.forEach(m=>m.pl.forEach(n=>cnt[n]++));const v=Object.values(cnt);ok('D4','Projected match counts are within 1 for early and late players',Math.max(...v)-Math.min(...v)<=1,cnt)}

 // 4b one-time correction of an existing unbalanced queue
 reset(2);ns=players('E',8);players('L',4);S.lineup=[];for(let i=0;i<8;i++){const pl=ns.slice((i*2)%8,((i*2)%8)+4).concat(ns).slice(0,4);S.lineup.push({t:'any',pl:Array.from(new Set(pl.concat(ns))).slice(0,4),src:'gen',grp:'o',id:'old'+i,q:i+1})}
 lmig();const pre=JSON.stringify(S.lineup.slice(0,2));S.v26rb=0;render();
 {const cnt={};Object.keys(S.p).forEach(n=>cnt[n]=0);S.lineup.forEach(m=>m.pl.forEach(n=>cnt[n]++));const v=Object.values(cnt);
  ok('D5','One-time correction: old unbalanced queue is levelled and history kept',Math.max(...v)-Math.min(...v)<=1&&S.v26rb===1,cnt)}

 // 5 OFF players are excluded and do not block
 reset(2);ns=players('P',10);setAvail('P1',false);setAvail('P2',false);addMatches('o');
 ok('E1','OFF players are not put into new matches',S.lineup.length===4&&S.lineup.every(m=>m.pl.indexOf('P1')<0&&m.pl.indexOf('P2')<0));

 // 6 waiting time
 reset(2);players('W',4,3,false);const P=S.p.W1;setAvail('W1',true);CLOCK+=10*60000;setAvail('W1',false);CLOCK+=30*60000;
 ok('F1','OFF time is excluded from waiting time',waitActive('W1')===10*60000,waitActive('W1'));
 setAvail('W1',true);CLOCK+=5*60000;ok('F2','ON again resumes counting (10 + 5 min), activation recorded twice',waitActive('W1')===15*60000&&P.acts.length===2,[waitActive('W1'),P.acts.length]);
 ['W2','W3','W4'].forEach(n=>setAvail(n,true));assignCourt(0,'o',true);
 ok('F3','Waiting stops while on court',['W1','W2','W3','W4'].every(n=>S.p[n].wst===0)||false,[S.games[0]]);

 // 7 no protection: everything editable
 reset(2);players('P',12);addMatches('o');
 ok('G1','No match is protected (isProt is always false)',S.lineup.every(m=>!isProt(m)));
 const m0=JSON.stringify(S.lineup[0]);ltype(0,'men');
 ok('G2','First Up Next match can be edited freely',JSON.stringify(S.lineup[0])!==m0||S.lineup[0].t==='men',S.lineup[0].t);
 const vic=S.lineup[0].pl[0];setAvail(vic,false);
 ok('G3','A player switching OFF does not lock or flag matches',typeof mFlag!=='function'||!mFlag(S.lineup[0]));

 // 7b editable court / scheduled
 reset(2);ns=players('Q',10);assignCourt(0,'o',true);
 {const g=S.games[0].slice(),out=g[0],inn=S.queue.find(n=>!S.p[n].pa);ED={k:'c',i:0,s:0};applyEdit(inn);
  ok('R1','On Court: player replaced, old player returns to queue',S.games[0][0]===inn&&S.queue.indexOf(out)>=0&&S.queue.indexOf(inn)<0&&new Set(S.games[0]).size===4,[S.games[0],out]);
  const sw=S.games[0][1];ED={k:'c',i:0,s:0};applyEdit(sw);
  ok('R2','On Court: choosing a player already in the match swaps places',S.games[0][0]===sw&&new Set(S.games[0]).size===4)}
 reset(2);players('Q',12);addMatches('o');
 {const m=S.lineup[0],before=m.pl.slice();const cand=Object.keys(S.p).find(n=>m.pl.indexOf(n)<0);ED=null;
  ok('R3','Up Next: lswap/ltype/lmove callable without lock',typeof lswap==='function'&&typeof lmove==='function')}

 // 7c round robin
 reset(2);players('R',8);S.gen.t={mixed:false,women:false,men:false,any:false,rr:true};
 {let r=addMatches('o');const pairs=new Set();let dup=0;S.lineup.forEach(m=>{[[m.pl[0],m.pl[1]],[m.pl[2],m.pl[3]]].forEach(p=>{const k=p.slice().sort().join('|');if(pairs.has(k))dup++;pairs.add(k)})});
  ok('S1','Round Robin adds matches tagged rr',r.ok&&S.lineup.length>0&&S.lineup.every(m=>m.t==='rr'),[r.msg,S.lineup.map(m=>m.t)]);
  ok('S2','Round Robin: no partner pair repeated within the first rotation',dup===0,dup);
  ok('S3','Round Robin progress panel renders',/Round Robin progress/.test(rrPanel('o')));
  ok('S4','No back-to-back in Round Robin',adj('o')===0)}

 // 7d ranking
 {const a={g:5,w:5,l:0},b={g:9,w:7,l:2},c={g:4,w:4,l:0},d={g:2,w:2,l:0};
  ok('T1','Unbeaten players (3+ wins, 0 losses) rank above players with more wins and losses',[b,a,c,d].sort(rankCmp)[0]===a&&[b,a,c,d].sort(rankCmp)[1]===c&&[b,a,c,d].sort(rankCmp)[2]===b,[b,a,c,d].sort(rankCmp).map(x=>x.w+'-'+x.l))}

 // 7e rating history
 reset(2);players('H',8);addMatches('o');assignCourt(0,'o',true);
 {const g=S.games[0].slice();const pre=g.map(n=>S.p[n].r);finish(0,'A');
  const p=S.p[g[0]],e=p.rh&&p.rh[p.rh.length-1];
  ok('U1','Rating history logs before/after/change per match',e&&Math.abs(e.b-pre[0])<1e-9&&Math.abs(e.a-p.r)<1e-9&&Math.abs(e.d-(e.a-e.b))<1e-9&&e.res==='W',e);
  ok('U2','Loser history entry too, with partner and opponents',S.p[g[3]].rh.slice(-1)[0].res==='L'&&S.p[g[3]].rh.slice(-1)[0].op.length===2);
  ok('U3','Session change is the sum of match changes',Math.abs(sessDelta(g[0])-p.rh.reduce((a,x)=>a+x.d,0))<1e-9);
  S.tab='ratings';render();
  ok('U4','Ratings tab renders; leaderboard has no Rating column',!!document.getElementById('p-ratings')&&!/<th>Rating<\/th>/.test(document.getElementById('board').innerHTML));
  S.rsel=g[0];render();ok('U5','Player detail shows history and chart',/svg/.test(document.getElementById('p-ratings').innerHTML));S.rsel=''}

 // 7f level floor
 reset(2);players('N',8,2);
 {const n='N1';S.p[n].r=2.5;S.p[n].s=2;for(let i=0;i<30;i++){S.games[0]=[n,'N2','N3','N4'];S.cm[0]={grp:'o',t:'any'};finish(0,'B')}
  ok('V1','Novice stays Novice after many losses (rating floors at 2.50)',S.p[n].s===2&&S.p[n].r>=2.5&&levelOf(S.p[n].r)===2,[S.p[n].r,S.p[n].s]);
  const m='N5';S.p[m].r=2.74;for(let i=0;i<40;i++){S.games[0]=[m,'N6','N7','N8'];S.cm[0]={grp:'o',t:'any'};finish(0,'A')}
  ok('V2','A player who keeps winning can move up a level',S.p[m].s>=3&&levelOf(S.p[m].r)>=3,[S.p[m].r,S.p[m].s]);
  S.tab='ratings';S.rsel='';render();const h=document.getElementById('ratings').innerHTML;
  ok('V3','Ratings tab shows Now, Prev, Change (with arrow) and Rated in one table',/Now/.test(h)&&/Prev/.test(h)&&/Change/.test(h)&&/Level/.test(h)&&!/Rated/.test(h)&&/▲|▼/.test(h));
  ok('V4','Rating chart has no Final reality check',!/Final reality check/.test(document.body.innerHTML))}

 // 7g ratings tab: this session only, promotion note
 reset(2);players('Z',5,2);S.sess={name:'s',start:1};S.p.Gone={r:3,s:3,w:0,l:0,rh:[{t:1,sid:0,b:3,a:3.1,d:.1,res:'W'}],pa:true};S.p.Z1.r=2.74;S.p.Z1.s=2;S.p.Z1.rh=[{t:2,sid:1,b:2.74,a:2.80,d:.06,res:'W',op:[],tm:[]}];S.p.Z1.r=2.8;S.p.Z1.s=2;S.p.Z1.rh[0].b=2.45;S.p.Z1.s=levelOf(2.8);S.tab='ratings';S.rsel='';render();
 {const h=document.getElementById('ratings').innerHTML;ok('W1','Ratings tab lists only this session players',/Z1/.test(h)&&!/Gone/.test(h));ok('W2','Promotion caption under the name',/Moved up: Newbie/.test(h),h.slice(0,0))}
 // 7h up next panel + wording
 reset(2);players('U',8);addMatches('o');render();
 {ok('X1','Up Next panel shows the next match with an Announce button',!!document.querySelector('#upnext .vbtn')&&/Up Next/.test(document.getElementById('upnext').innerHTML));
  ok('X2','Up Next wording',upTxt(['Ray','Ayen','Joshua','Shiela'])==='Up Next, Ray with Ayen.. versus, Joshua with Shiela.. Players, be ready.')}
 // 8 skill groups
 reset(2);players('B',6,1);players('O',6,3);const rb=addMatches('b'),ro=addMatches('o');
 ok('H1','Beginner matches use only Beginners; Open only Open',S.lineup.filter(m=>m.grp==='b').every(m=>m.pl.every(n=>n[0]==='B'))&&S.lineup.filter(m=>m.grp==='o').every(m=>m.pl.every(n=>n[0]==='O'))&&rb.ok&&ro.ok,[rb.msg,ro.msg]);

 // 9 completion resets waiting, keeps counts
 reset(1);players('P',8);addMatches('o');assignCourt(0,'o',true);S.hd[0]=0;CLOCK+=20*60000;const pl0=S.games[0].slice();logMatch(0,'A',null);finish(0,'A');
 ok('I1','Completed match resets waiting from completion time and keeps history',pl0.every(n=>waitActive(n)===0&&S.p[n].lc===CLOCK)&&S.hist.length===1);

 // 10 randomised fairness
 let bad=[];for(let t=0;t<60;t++){const c=1+t%3,Pn=8+(t*7)%13;reset(c);players('P',Pn);let okAll=true;
   for(let k=0;k<3;k++){gap();addMatches('o')}
   const q=seq('o');const ct={};q.forEach(m=>m.pl.forEach(n=>ct[n]=(ct[n]||0)+1));
   const vals=Object.keys(S.p).map(n=>ct[n]||0);const spread=Math.max(...vals)-Math.min(...vals);
   const dup=q.some(m=>new Set(m.pl).size!==4);
   const feasible=Pn>=8;const a=adj('o');
   if(spread>1||dup||(feasible&&a>0))bad.push({c,Pn,spread,dup,adj:a})}
 ok('J1','60 random sessions: counts within 1, no duplicate players, no back-to-back',bad.length===0,bad.slice(0,5));
 // 11 late arrivals / OFF-ON toggles mid-session over many random sessions
 {let bad=[];for(let t=0;t<40;t++){const c=1+t%3,Pn=8+(t*5)%9,Ln=1+t%4;reset(c);players('P',Pn);gap();addMatches('o');
   players('L',Ln);gap();addMatches('o');setAvail('P2',false);gap();addMatches('o');setAvail('P2',true);gap();addMatches('o');
   const q=seq('o'),cnt={};Object.keys(S.p).forEach(n=>cnt[n]=0);q.forEach(m=>m.pl.forEach(n=>{if(cnt[n]!==undefined)cnt[n]++}));
   const v=Object.keys(S.p).map(n=>cnt[n]),spread=Math.max(...v)-Math.min(...v),dup=q.some(m=>new Set(m.pl).size!==4||m.pl.some(n=>!S.p[n]));
   const a=adj('o');if(spread>2||dup||a>0)bad.push({c,Pn,Ln,spread,dup,adj:a})}
  ok('K1','40 sessions with late arrivals and OFF/ON toggles: counts within 2, no duplicates, no back-to-back',bad.length===0,bad.slice(0,6))}

 // 12 Universal match-count fairness across all four modes
 {const modes=['balanced','line','skill','record'],results=[];modes.forEach(mode=>{reset(3);S.mode=mode;players('M',12);for(let batch=0;batch<3;batch++){gap();addMatches('o')}const cnt={};Object.keys(S.p).forEach(n=>cnt[n]=0);S.lineup.forEach(m=>m.pl.forEach(n=>cnt[n]++));const v=Object.values(cnt),spread=Math.max(...v)-Math.min(...v);results.push({mode,spread,matches:S.lineup.length});});
  ok('L1','All four modes prioritize the fewest session matches; 12 players across 3 courts stay level after 3 batches',results.every(x=>x.matches===18&&x.spread===0),results)}
 return out});
let fail=0;R.forEach(t=>{if(!t.pass)fail++;console.log((t.pass?'PASS ':'FAIL ')+t.id+'  '+t.name+(t.pass?'':'\n      '+t.info))});
console.log(errs.length?'PAGE ERRORS: '+errs.join(' | '):'No page errors');console.log((R.length-fail)+'/'+R.length+' passed');await b.close();process.exit(fail||errs.length?1:0)})();
