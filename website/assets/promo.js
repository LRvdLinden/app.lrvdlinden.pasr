/* Pasr Zakelijk promotiemateriaal — dezelfde kaartgegevens als het dashboard.
 * De kaart wordt op Canvas getekend (geen AI, geen fictieve logo's). */
(function () {
  "use strict";
  var formats = [
    { id:"square", name:"Instagram / Facebook vierkant", w:1080, h:1080 },
    { id:"portrait", name:"Instagram staand", w:1080, h:1350 },
    { id:"story", name:"Story / WhatsApp-status", w:1080, h:1920 },
    { id:"wide", name:"Website / LinkedIn banner", w:1200, h:630 },
    { id:"flyer", name:"A4-printposter", w:2480, h:3508 }
  ];
  var stampURL = "/assets/pasr-stamp.svg";
  var iconURL = "/assets/icon.png";
  function load(url) {
    return new Promise(function(resolve) {
      if (!url) return resolve(null);
      var img = new Image(); img.onload = function(){ resolve(img); };
      img.onerror = function(){ resolve(null); }; img.src = url;
    });
  }
  function color(c, fallback) { return /^#[0-9a-f]{6}$/i.test(c || "") ? c : (fallback || "#6A5CFF"); }
  function rgb(hex) { return [1,3,5].map(function(i){ return parseInt(hex.slice(i,i+2),16); }); }
  function luminance(hex) {
    var v=rgb(hex).map(function(c){c/=255;return c<=0.04045?c/12.92:Math.pow((c+0.055)/1.055,2.4);});
    return v[0]*.2126+v[1]*.7152+v[2]*.0722;
  }
  function mix(hex, to, part) {
    return "rgb("+rgb(hex).map(function(x){return Math.round(x*(1-part)+to*part);}).join(",")+")";
  }
  function rr(ctx,x,y,w,h,r,fill,stroke,sw){
    ctx.beginPath();ctx.roundRect(x,y,w,h,Math.min(r,w/2,h/2));
    if(fill){ctx.fillStyle=fill;ctx.fill();}
    if(stroke){ctx.lineWidth=sw||2;ctx.strokeStyle=stroke;ctx.stroke();}
  }
  function text(ctx,s,x,y,font,fill,align,maxWidth){
    ctx.font=font;ctx.fillStyle=fill;ctx.textAlign=align||"left";ctx.textBaseline="alphabetic";
    ctx.fillText(String(s||""),x,y,maxWidth);
  }
  function wrap(ctx,s,maxW,font,maxLines){
    ctx.font=font; var words=String(s||"").split(/\s+/),lines=[],line="";
    words.forEach(function(w){var next=line?line+" "+w:w;
      if(line&&ctx.measureText(next).width>maxW){lines.push(line);line=w;}else line=next;
    });
    if(line)lines.push(line);
    if(lines.length>maxLines){lines=lines.slice(0,maxLines);var i=lines.length-1;
      while(lines[i].length&&ctx.measureText(lines[i]+"…").width>maxW)lines[i]=lines[i].slice(0,-1);
      lines[i]+="…";}
    return lines;
  }
  function drawImg(ctx,img,x,y,w,h) {
    if(!img)return;var scale=Math.min(w/img.width,h/img.height);
    var iw=img.width*scale,ih=img.height*scale;ctx.drawImage(img,x+(w-iw)/2,y+(h-ih)/2,iw,ih);
  }
  function qrGrid(ctx, url, x, y, s) {
    if(typeof qrcode!=="function")return;
    var qr=qrcode(0,"M");qr.addData(url);qr.make();
    var n=qr.getModuleCount(),unit=s/(n+8);
    ctx.fillStyle="#FFFFFF";ctx.fillRect(x,y,s,s);
    ctx.fillStyle="#17162A";
    for(var row=0;row<n;row++)for(var col=0;col<n;col++)
      if(qr.isDark(row,col))ctx.fillRect(x+(col+4)*unit,y+(row+4)*unit,Math.ceil(unit),Math.ceil(unit));
  }
  function stampMark(ctx, image, x,y,side,ink) {
    if(!image){ctx.strokeStyle=ink;ctx.lineWidth=2;ctx.beginPath();ctx.arc(x+side/2,y+side/2,side*.46,0,Math.PI*2);ctx.stroke();return;}
    // Het SVG is de officiële Pasr-zegel; altijd ongewijzigde vorm.
    var layer=document.createElement("canvas");layer.width=Math.ceil(side*2);layer.height=Math.ceil(side*2);
    var lc=layer.getContext("2d");lc.drawImage(image,0,0,layer.width,layer.height);
    lc.globalCompositeOperation="source-in";lc.fillStyle=ink;lc.fillRect(0,0,layer.width,layer.height);
    ctx.drawImage(layer,x,y,side,side);
  }
  /* ---- Ontwerp 2026-11: bedrijfskleur als hoofdkleur, kaart/ticket groot, QR in eigen blok, klein Pasr-logo onderaan.
   * Alle maten hieronder zijn in een logisch canvas van 1080 breed (breed formaat: 1080 × 567). ---- */
  var FM = {
    square:{w:1080,h:1080,hs:80,kt:22,qs:150}, portrait:{w:1080,h:1350,hs:92,kt:34,qs:190},
    story:{w:1080,h:1920,hs:118,kt:60,qs:260,col:1}, flyer:{w:1080,h:1527.6,hs:100,kt:60,qs:250,col:1},
    wide:{w:1080,h:567,wide:1}
  };
  var FD = "800 {s}px 'Bricolage Grotesque',Figtree,sans-serif", FB = "{w} {s}px Figtree,sans-serif";
  function fd(s){return FD.replace("{s}",s);} function fb(w,s){return FB.replace("{w}",w).replace("{s}",s);}
  function hexOf(r){return "#"+r.map(function(x){return Math.max(0,Math.min(255,Math.round(x))).toString(16).padStart(2,"0");}).join("");}
  function mixHex(hex,to,part){return hexOf(rgb(hex).map(function(x){return x*(1-part)+to*part;}));}
  function rgba(hex,a){return "rgba("+rgb(hex).join(",")+","+a+")";}
  function spaced(ctx,s,x,y,font,fill,sp,align){
    ctx.font=font;ctx.fillStyle=fill;ctx.textBaseline="middle";ctx.textAlign="left";
    var chars=String(s).split(""),w=0;chars.forEach(function(c){w+=ctx.measureText(c).width+sp;});w-=sp;
    var cx=align==="center"?x-w/2:align==="right"?x-w:x;
    chars.forEach(function(c){ctx.fillText(c,cx,y);cx+=ctx.measureText(c).width+sp;});
  }
  function line(ctx,s,x,y,font,fill,align){ctx.font=font;ctx.fillStyle=fill;ctx.textAlign=align||"left";ctx.textBaseline="middle";ctx.fillText(s,x,y);}
  function fit(ctx,s,maxW,font){ctx.font=font;s=String(s||"");if(ctx.measureText(s).width<=maxW)return s;
    while(s.length&&ctx.measureText(s+"…").width>maxW)s=s.slice(0,-1);return s+"…";}
  function wrapRuns(ctx,runs,maxW,font,maxLines){
    ctx.font=font;var words=[];runs.forEach(function(r){String(r.t||"").split(/\s+/).filter(Boolean).forEach(function(w){words.push({w:w,c:r.c});});});
    var lines=[],cur=[],curW=0,sp=ctx.measureText(" ").width;
    words.forEach(function(wd){var ww=ctx.measureText(wd.w).width;
      if(cur.length&&curW+sp+ww>maxW){lines.push(cur);cur=[wd];curW=ww;}else{curW+=(cur.length?sp:0)+ww;cur.push(wd);}});
    if(cur.length)lines.push(cur);
    if(lines.length>maxLines){lines=lines.slice(0,maxLines);var l=lines[maxLines-1];l[l.length-1]={w:l[l.length-1].w.replace(/.$/,"")+"…",c:l[l.length-1].c};}
    return lines;
  }
  function drawRuns(ctx,ln,x,y,font){
    ctx.font=font;ctx.textBaseline="middle";ctx.textAlign="left";var cx=x,sp=ctx.measureText(" ").width;
    if("letterSpacing" in ctx)ctx.letterSpacing="-0.025em";
    ln.forEach(function(wd){ctx.fillStyle=wd.c;ctx.fillText(wd.w,cx,y);cx+=ctx.measureText(wd.w).width+sp;});
    if("letterSpacing" in ctx)ctx.letterSpacing="0px";
  }
  function nlDate(d){var t=new Date(d);return isNaN(t)?"":t.toLocaleDateString("nl-NL",{day:"numeric",month:"long",year:"numeric",timeZone:"Europe/Amsterdam"});}
  function evParts(iso){var t=new Date(iso);if(isNaN(t))return null;
    function f(o){return new Intl.DateTimeFormat("nl-NL",Object.assign({timeZone:"Europe/Amsterdam"},o)).format(t);}
    return {day:f({day:"numeric"}),month:f({month:"long"}).toUpperCase(),weekday:f({weekday:"long"}),time:f({hour:"2-digit",minute:"2-digit",hourCycle:"h23"})};}
  function theme(card,dark){
    var brand=color(card.color),acc=brand,t=0,on=luminance(brand)>.45?"#17162A":"#FFFFFF";
    if(card.kind==="card"&&/^#[0-9a-f]{6}$/i.test(card.text_color||""))on=card.text_color;
    if(!dark){while(luminance(acc)>.18&&t<10){acc=mixHex(brand,0,.08*(++t));}}
    else{while(luminance(acc)<.30&&t<10){acc=mixHex(acc,255,.12);t++;}}
    return {brand:brand,on:on,acc:acc,b1:mixHex(brand,255,.16),b2:mixHex(brand,0,.24),dark:dark,
      fg:dark?"#FFFFFF":"#17162A",muted:dark?"#C9C6E9":"#55536B",panel:dark?"#2B2458":"#FFFFFF",
      shadow:dark?"rgba(0,0,0,.5)":rgba(mixHex(brand,0,.2),.38)};
  }
  function css160(ctx,w,h){var a=160*Math.PI/180,dx=Math.sin(a),dy=-Math.cos(a),len=Math.abs(w*dx)+Math.abs(h*dy),cx=w/2,cy=h/2;
    return ctx.createLinearGradient(cx-dx*len/2,cy-dy*len/2,cx+dx*len/2,cy+dy*len/2);}
  function background(ctx,w,h,T,wide){
    var g=css160(ctx,w,h);
    if(T.dark){g.addColorStop(0,"#17162A");g.addColorStop(1/1.4,mixHex(T.brand,0,.78));g.addColorStop(1,mixHex(T.brand,0,.78));}
    else{g.addColorStop(0,"#FFFFFF");g.addColorStop(1/1.3,mixHex(T.brand,255,.9));g.addColorStop(1,mixHex(T.brand,255,.9));}
    ctx.fillStyle=g;ctx.fillRect(0,0,w,h);
    var gc=T.dark?rgba(mixHex(T.brand,0,.55),.35):rgba(mixHex(T.brand,255,.78),.55);
    ctx.fillStyle=gc;ctx.beginPath();ctx.arc(w-70,70,450,0,Math.PI*2);ctx.fill();
    if(!wide){ctx.globalAlpha=.6;ctx.beginPath();ctx.arc(-10,h-50,350,0,Math.PI*2);ctx.fill();ctx.globalAlpha=1;}
  }
  function drawLogoTile(ctx,img,letter,x,y,s,T,fill,ink){
    ctx.save();ctx.beginPath();ctx.roundRect(x,y,s,s,s*.24);ctx.clip();
    ctx.fillStyle=img?"#FFFFFF":fill;ctx.fillRect(x,y,s,s);
    if(img)drawImg(ctx,img,x,y,s,s);else line(ctx,letter,x+s/2,y+s/2+s*.02,fd(Math.round(s*.52)),ink,"center");
    ctx.restore();
  }
  function lockWidth(ctx,k){ctx.font=fd(54);return (60+14+ctx.measureText("pasr").width)*k;}
  function drawLock(ctx,icon,x,y,k,dark){
    ctx.save();ctx.translate(x,y);ctx.scale(k,k);
    ctx.beginPath();ctx.roundRect(0,0,60,60,14);ctx.fillStyle="#17162A";ctx.fill();
    if(icon){ctx.save();ctx.clip();drawImg(ctx,icon,0,0,60,60);ctx.restore();}
    line(ctx,"pasr",74,31,fd(54),dark?"#FFFFFF":"#17162A");ctx.restore();
  }
  function drawTop(ctx,x,y,s,T,imgs,card,biz){
    drawLogoTile(ctx,imgs.logo,(biz||"P").slice(0,1).toUpperCase(),x,y,s,T,T.brand,T.on);
    var k=s/92;line(ctx,fit(ctx,biz,s>80?680:340,fd(Math.round(38*k))),x+s+22*k,y+s/2-17*k,fd(Math.round(38*k)),T.fg);
    if(card.city)line(ctx,card.city,x+s+22*k,y+s/2+19*k,fb(600,Math.round(26*k)),T.muted);
  }
  function drawQrPanel(ctx,x,y,w,qs,qb,T,url,b,sub,pad){
    pad=pad||22;var h=qs+pad*2;
    ctx.save();ctx.shadowColor="rgba(30,20,90,.14)";ctx.shadowBlur=40;ctx.shadowOffsetY=14;
    ctx.beginPath();ctx.roundRect(x,y,w,h,Math.max(24,pad*1.55));ctx.fillStyle=T.panel;ctx.fill();ctx.restore();
    ctx.save();ctx.beginPath();ctx.roundRect(x+pad,y+pad,qs,qs,14);ctx.clip();qrGrid(ctx,url,x+pad,y+pad,qs);ctx.restore();
    var tx=x+pad+qs+pad*1.35,tw=w-(tx-x)-pad;
    var lines=wrapRuns(ctx,[{t:b,c:T.fg}],tw,fd(qb),3),sh=qb*.6*1.2,bh=lines.length*qb*1.05+8+sh,ty=y+(h-bh)/2;
    lines.forEach(function(l,i){drawRuns(ctx,l,tx,ty+qb*1.05*(i+.5),fd(qb));});
    line(ctx,sub,tx,ty+lines.length*qb*1.05+8+sh/2,fb(600,Math.round(qb*.6)),T.muted);
    return h;
  }
  function drawNote(ctx,x,y,t,s,T,k){
    line(ctx,t,x,y+17*k,fb(800,Math.round(34*k)),T.fg);line(ctx,s,x,y+17*k+42*k,fb(600,Math.round(30*k)),T.muted);
  }
  function stampCard(ctx,card,T,imgs){
    var w=900,h=560,pad=52,total=Math.min(30,Math.max(2,Number(card.stamps_total)||10)),filled=Math.min(total-1,Math.max(1,Math.round(total*.4)));
    var cols=total<=5?total:total<=10?5:total<=12?6:total<=21?7:8,rows=Math.ceil(total/cols);
    var area=h-pad*2-172,cell=Math.min(104,(w-pad*2-(cols-1)*18)/cols,(area-(rows-1)*14)/rows),rgap=rows>1?Math.min(26,(area-rows*cell)/(rows-1)):0;
    ctx.save();ctx.shadowColor=T.shadow;ctx.shadowBlur=70;ctx.shadowOffsetY=36;
    var g=ctx.createLinearGradient(0,0,w,h);g.addColorStop(0,T.b1);g.addColorStop(.55,T.brand);g.addColorStop(1,T.b2);
    ctx.beginPath();ctx.roundRect(0,0,w,h,46);ctx.fillStyle=g;ctx.fill();ctx.restore();
    drawLogoTile(ctx,imgs.logo,(card.name||"P").slice(0,1).toUpperCase(),pad,pad,100,T,"rgba(255,255,255,.22)",T.on);
    line(ctx,fit(ctx,card.name,w-pad*2-124,fd(48)),pad+124,pad+34,fd(48),T.on);
    line(ctx,fit(ctx,[card.business,card.city].filter(Boolean).join(" · "),w-pad*2-124,fb(600,26)),pad+124,pad+74,fb(600,26),T.on);
    var top=pad+100+18,bottom=h-pad-36-18,gh=rows*cell+(rows-1)*rgap,gy=top+(bottom-top-gh)/2,pitch=(w-pad*2)/cols;
    for(var i=0;i<total;i++){
      var cx=pad+(i%cols+.5)*pitch-cell/2,cy=gy+Math.floor(i/cols)*(cell+rgap);
      if(i<filled)stampMark(ctx,imgs.stamp,cx,cy,cell,T.on);
      else{ctx.save();ctx.setLineDash([9,7]);ctx.strokeStyle=T.on;ctx.globalAlpha=.55;ctx.lineWidth=3;
        ctx.beginPath();ctx.arc(cx+cell/2,cy+cell/2,cell/2-2,0,Math.PI*2);ctx.stroke();ctx.restore();}
    }
    line(ctx,fit(ctx,card.reward,w*.62,fb(800,30)),pad,h-pad-18,fb(800,30),T.on);
    line(ctx,total+" stempels",w-pad,h-pad-18,fb(800,30),T.on,"right");
    return {w:w,h:h};
  }
  function ticket(ctx,card,T,imgs,kind){
    var w=900,h=500,sw=250,dx=w-sw;
    ctx.save();ctx.shadowColor=T.shadow;ctx.shadowBlur=40;ctx.shadowOffsetY=30;
    var g=ctx.createLinearGradient(0,0,w,h);g.addColorStop(0,T.b1);g.addColorStop(.6,T.brand);g.addColorStop(1,T.b2);
    ctx.beginPath();ctx.roundRect(0,0,w,h,44);ctx.moveTo(dx+30,0);ctx.arc(dx,0,30,0,Math.PI*2,true);ctx.moveTo(dx+30,h);ctx.arc(dx,h,30,0,Math.PI*2,true);
    ctx.fillStyle=g;ctx.fill("evenodd");ctx.restore();
    ctx.save();ctx.setLineDash([12,10]);ctx.strokeStyle="rgba(255,255,255,.55)";ctx.lineWidth=4;
    ctx.beginPath();ctx.moveTo(dx,62);ctx.lineTo(dx,h-62);ctx.stroke();ctx.restore();
    var lw=dx-100,on=T.on;
    if(kind==="event"){
      var p=evParts(card.starts_at)||{day:"",month:"",weekday:"",time:""};
      line(ctx,p.day,50,50+95,fd(190),on);
      spaced(ctx,p.month,50,50+215,fb(800,36),on,5);
      line(ctx,fit(ctx,p.weekday+(p.time?" · "+p.time+" uur":""),lw,fb(700,34)),50,h-44-60,fb(700,34),on);
      line(ctx,fit(ctx,card.address||"Locatie volgt",lw,fb(600,26)),50,h-44-20,fb(600,26),on);
      stampMark(ctx,imgs.stamp,dx+(sw-120)/2,(h-211)/2,120,on);
      spaced(ctx,"GRATIS",dx+sw/2,(h-211)/2+120+14+13,fb(800,22),on,2.2,"center");
      line(ctx,"Ticket",dx+sw/2,(h-211)/2+120+14+26+14+19,fd(34),on,"center");
    }else{
      var big=card.discount_type==="percent"?String(card.discount_value):new Intl.NumberFormat("nl-NL",{style:"currency",currency:"EUR",minimumFractionDigits:0}).format(card.discount_value||0);
      ctx.font=fd(200);line(ctx,big,50,50+90,fd(200),on);
      if(card.discount_type==="percent"){var bw=ctx.measureText(big).width;line(ctx,"%",50+bw+6,50+58,fd(100),on);}
      spaced(ctx,"KORTING",50,50+215,fb(800,40),on,5.6);
      line(ctx,fit(ctx,card.business||"",lw,fb(700,34)),50,h-44-45,fb(700,34),on);
      line(ctx,fit(ctx,card.ends_at?"Geldig t/m "+nlDate(card.ends_at):"Vraag naar de actievoorwaarden",lw,fb(600,26)),50,h-44-12,fb(600,26),on);
      stampMark(ctx,imgs.stamp,dx+(sw-120)/2,(h-211)/2,120,on);
      spaced(ctx,"EXCLUSIEF IN",dx+sw/2,(h-211)/2+120+14+13,fb(800,22),on,2.2,"center");
      line(ctx,"Pasr",dx+sw/2,(h-211)/2+120+14+26+14+19,fd(34),on,"center");
    }
    return {w:w,h:h};
  }
  function visual(ctx,card,T,imgs,kind){return kind==="card"?stampCard(ctx,card,T,imgs):ticket(ctx,card,T,imgs,kind);}
  function visSize(kind){return kind==="card"?{w:900,h:560}:{w:900,h:500};}
  function copyFor(card,kind){
    var biz=card.business||card.name||"";
    if(kind==="card")return {kick:"Digitale spaarkaart",runs:[{t:"Spaar digitaal bij",c:"fg"},{t:biz,c:"acc"}]};
    if(kind==="event")return {kick:"Gratis event",runs:[{t:card.name||card.title||"Event",c:"fg"}]};
    return {kick:kind==="coupon"?"Kortingscoupon":"Actiecode",runs:[{t:card.title||card.name||"Korting",c:"fg"}]};
  }
  async function render(card,formatId,theme) {
    var format=formats.find(function(f){return f.id===formatId;})||formats[0],f=FM[format.id]||FM.square;
    var kind=card.kind==="coupon"?"coupon":card.kind==="code"?"code":card.kind==="event"?"event":"card";
    var scale=format.w/f.w,canvas=document.createElement("canvas");canvas.width=format.w;canvas.height=format.h;
    var ctx=canvas.getContext("2d",{alpha:false});ctx.scale(scale,scale);
    var logoRaw=String(card.logo||"");
    var imgs=await Promise.all([load(iconURL),load(stampURL),load(logoRaw&&/^[A-Za-z0-9+/=]+$/.test(logoRaw)?
      "data:image/"+(logoRaw.indexOf("/9j/")===0?"jpeg":"png")+";base64,"+logoRaw:null)]);
    imgs={icon:imgs[0],stamp:imgs[1],logo:imgs[2]};
    try{if(document.fonts&&document.fonts.ready)await document.fonts.ready;}catch(e){}
    var dark=theme==="dark",T=theme_(card,dark,kind),W=f.w,H=f.h,cp=copyFor(card,kind);
    var biz=card.business||card.name||"";
    background(ctx,W,H,T,!!f.wide);
    var runs=cp.runs.map(function(r){return {t:r.t,c:r.c==="acc"?T.acc:T.fg};});
    var published=card.published!==false&&(kind!=="event"||(card.status!=="draft"&&card.status!=="cancelled"));
    var hasQr=(kind==="card"||kind==="event")&&published;
    var url=card.join_url||(kind==="event"?"https://pasr.nl/add/e/"+card.id:"https://pasr.nl/zakelijk/kaart/"+card.id+"/");
    var qrTitle=kind==="event"?"Scan en meld je aan":"Scan en spaar mee",qrSub=kind==="event"?"gratis via de Pasr-app":"met de Pasr-app";
    var noteT=kind==="card"?"Scan-QR volgt na publicatie":kind==="event"?"Aanmeld-QR volgt na publicatie":"Exclusief in de Pasr-app";
    var noteS=kind==="card"?"Conceptkaart":kind==="event"?"Conceptevent":"Download Pasr: Klantenkaarten";
    var vs=visSize(kind);
    if(f.wide){
      var PX=56,PY=46,tw=1080-PX*2-500-30;
      if(kind!=="card"||true)drawTop(ctx,PX,PY,70,T,imgs,card,biz);
      var hs=58,lines=wrapRuns(ctx,runs,tw,fd(hs),3),lh=hs*1.02,midH=21*1.2+10+lines.length*lh;
      var botH=hasQr?148:50,free=(H-PY*2)-70-midH-botH,my=PY+70+free/2;
      spaced(ctx,cp.kick.toUpperCase(),PX,my+12,fb(800,21),T.acc,1.9);
      lines.forEach(function(l,i){drawRuns(ctx,l,PX,my+21*1.2+10+lh*(i+.5),fd(hs));});
      if(hasQr)drawQrPanel(ctx,PX,H-PY-148,390,120,32,T,url,qrTitle,qrSub,14);
      else line(ctx,kind==="card"||kind==="event"?noteS:(card.ends_at?"Geldig t/m "+nlDate(card.ends_at):noteS),PX,H-PY-20,fb(600,22),T.muted);
      var k=.5,rh=vs.h*k+26+54,ry=PY+((H-PY*2)-rh)/2,rcx=1080-PX-250;
      ctx.save();ctx.translate(rcx,ry+vs.h*k/2);ctx.rotate(-3*Math.PI/180);ctx.scale(k,k);ctx.translate(-vs.w/2,-vs.h/2);
      visual(ctx,card,T,imgs,kind);ctx.restore();
      drawLock(ctx,imgs.icon,rcx-lockWidth(ctx,.9)/2,ry+vs.h*k+26,.9,dark);
      return canvas;
    }
    var L=76,IW=W-152,y=72;
    if(kind!=="card"){drawTop(ctx,L,y,92,T,imgs,card,biz);y+=92+10;}
    y+=f.kt;spaced(ctx,cp.kick.toUpperCase(),L,y+16,fb(800,27),T.acc,2.4);y+=32+16;
    var hl=wrapRuns(ctx,runs,IW,fd(f.hs),4),hh=f.hs*1.02;
    hl.forEach(function(l,i){drawRuns(ctx,l,L,y+hh*(i+.5),fd(f.hs));});y+=hl.length*hh;
    var qs=f.qs,qb=f.col?60:44,noteH=34*1.3+4+30*1.35,blockH=hasQr?qs+44:noteH,footH=f.col?blockH+40+60:Math.max(blockH,60);
    var footTop=H-64-footH,lockW=lockWidth(ctx,1);
    var top=y+20,bot=footTop-20,k2=Math.min(1,(bot-top)/vs.h);
    ctx.save();ctx.translate(W/2,top+(bot-top)/2);ctx.scale(k2,k2);ctx.translate(-vs.w/2,-vs.h/2);visual(ctx,card,T,imgs,kind);ctx.restore();
    var qw=f.col?IW:IW-34-lockW;
    if(hasQr)drawQrPanel(ctx,L,footTop,qw,qs,qb,T,url,qrTitle,qrSub);
    else drawNote(ctx,L,footTop+(f.col?0:(footH-noteH)/2),noteT,noteS,T,1);
    if(f.col)drawLock(ctx,imgs.icon,(W-lockW)/2,H-64-60,1,dark);
    else drawLock(ctx,imgs.icon,W-76-lockW,footTop+(footH-60)/2,1,dark);
    return canvas;
  }
  function theme_(card,dark,kind){return theme(Object.assign({},card,{kind:kind}),dark);}
  function save(canvas,name){
    return new Promise(function(resolve){
      canvas.toBlob(async function(blob){
        if(!blob)return resolve(null);
        if(await nativeSave(blob,name))return resolve(blob);
        var url=URL.createObjectURL(blob),a=document.createElement("a");
        a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();
        setTimeout(function(){URL.revokeObjectURL(url);},5000);resolve(blob);
      },"image/png");
    });
  }
  function fileName(card,format,theme){
    var safe=String(card.title||card.name||"actie").normalize("NFKD").replace(/[\u0300-\u036f]/g,"").replace(/[^a-zA-Z0-9]+/g,"-").replace(/^-|-$/g,"");
    return "Pasr-"+safe+"-"+format+"-"+(theme==="dark"?"Donker":"Licht")+".png";
  }
  // ZIP-store zonder externe CDN of tracking (CRC32 + centrale directory).
  function zip(files) {
    var te=new TextEncoder(),parts=[],central=[],offset=0;
    var table=Array.from({length:256},function(_,n){for(var k=0;k<8;k++)n=(n&1)?0xEDB88320^(n>>>1):n>>>1;return n>>>0;});
    function crc(data){var c=-1;for(var i=0;i<data.length;i++)c=table[(c^data[i])&255]^(c>>>8);return(c^(-1))>>>0;}
    function header(len){return new DataView(new ArrayBuffer(len));}
    function u16(v,o,n){v.setUint16(o,n,true);}
    function u32(v,o,n){v.setUint32(o,n,true);}
    files.forEach(function(file){
      var name=te.encode(file.name),data=new Uint8Array(file.data),checksum=crc(data);
      var local=header(30);u32(local,0,0x04034b50);u16(local,4,20);u16(local,6,0x800);
      u32(local,14,checksum);u32(local,18,data.length);u32(local,22,data.length);u16(local,26,name.length);
      parts.push(local.buffer,name,data);
      var cent=header(46);u32(cent,0,0x02014b50);u16(cent,4,20);u16(cent,6,20);u16(cent,8,0x800);
      u32(cent,16,checksum);u32(cent,20,data.length);u32(cent,24,data.length);u16(cent,28,name.length);u32(cent,42,offset);
      central.push(cent.buffer,name);
      offset+=30+name.length+data.length;
    });
    var csize=central.reduce(function(n,x){return n+x.byteLength;},0);
    var end=header(22);u32(end,0,0x06054b50);u16(end,8,files.length);u16(end,10,files.length);
    u32(end,12,csize);u32(end,16,offset);
    return new Blob(parts.concat(central,[end.buffer]),{type:"application/zip"});
  }
  async function nativeSave(blob,name) {
    // Alleen in de eigen apps. JS-bridge wordt uitsluitend op pasr.nl geladen.
    var ios=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.pasrExport;
    var android=window.PasrAndroidExport;
    if(!ios&&!android)return false;
    var data=await new Promise(function(resolve,reject){
      var reader=new FileReader();reader.onload=function(){resolve(String(reader.result).split(",")[1]);};
      reader.onerror=reject;reader.readAsDataURL(blob);
    });
    var mime=blob.type||"application/octet-stream";
    if(ios){
      var raw=atob(data);
      ios.postMessage({operation:"begin",name:name,mime:mime,length:raw.length});
      for(var i=0;i<raw.length;i+=48000){
        var part=raw.slice(i,i+48000),bytes=new Uint8Array(part.length);
        for(var k=0;k<part.length;k++)bytes[k]=part.charCodeAt(k);
        var binary="";for(var j=0;j<bytes.length;j++)binary+=String.fromCharCode(bytes[j]);
        ios.postMessage({operation:"chunk",data:btoa(binary)});
      }
      ios.postMessage({operation:"end"});
    } else android.save(name,mime,data);
    return true;
  }
  async function blobSave(blob,name){
    if(await nativeSave(blob,name))return;
    var url=URL.createObjectURL(blob),a=document.createElement("a");
    a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();
    setTimeout(function(){URL.revokeObjectURL(url);},5000);
  }
  function mount(root,card,options) {
    options=options||{};
    var chosen=formats[0],theme="light",latest=null,revision=0;
    root.innerHTML='<section class="pz-promo"><div class="pz-promo-heading"><h2>Promotiemateriaal · '+escapeHTML(card.title||card.name)+
      '</h2><p>Gebruik de echte gegevens van deze '+(card.kind==='coupon'?'coupon':card.kind==='code'?'actiecode':card.kind==='event'?'event':'stempelkaart')+'. Ontwerpen in Licht en Donker.</p></div>'+
      '<div class="pz-promo-controls"><label>Formaat <select data-pz-format></select></label>'+
      '<fieldset><legend>Uitvoering</legend><label><input name="pz-theme" type="radio" value="light" checked> Licht</label>'+
      '<label><input name="pz-theme" type="radio" value="dark"> Donker</label></fieldset></div>'+
      '<div class="pz-promo-preview" aria-live="polite"><span data-pz-loading>Voorbeeld maken…</span><canvas data-pz-canvas></canvas></div>'+
      '<div class="pz-promo-actions"><button type="button" class="zk-btn" data-pz-download>Download PNG</button>'+
      '<button type="button" class="zk-btn ghost" data-pz-all>Download alle ontwerpen (ZIP)</button>'+
      (options.print?'<button type="button" class="zk-btn ghost" data-pz-print>Print A4/PDF</button>':"")+
      '</div><p class="pz-promo-note">'+(card.kind==='event'?'De QR-code opent de gratis aanmelding voor dit event. Bij een concept verschijnt geen werkende QR-code.':'De kaart is een promotiemodel, geen klantensaldo. Bij een conceptkaart verschijnt geen werkende QR-code.')+'</p></section>';
    var sel=root.querySelector("[data-pz-format]"),preview=root.querySelector("[data-pz-canvas]");
    formats.forEach(function(f){var o=document.createElement("option");o.value=f.id;o.textContent=f.name+" · "+f.w+" × "+f.h;sel.appendChild(o);});
    async function update() {
      var ver=++revision;root.querySelector("[data-pz-loading]").hidden=false;
      try{
        var canvas=await render(card,chosen.id,theme);
        if(ver!==revision)return;
        preview.width=canvas.width;preview.height=canvas.height;
        preview.getContext("2d").drawImage(canvas,0,0);latest=canvas;
        root.querySelector("[data-pz-loading]").hidden=true;
      }catch(e){root.querySelector("[data-pz-loading]").textContent="Voorbeeld kon niet worden gemaakt.";console.error(e);}
    }
    sel.addEventListener("change",function(){chosen=formats.find(function(x){return x.id===sel.value;})||formats[0];update();});
    root.querySelectorAll('input[name="pz-theme"]').forEach(function(el){
      el.addEventListener("change",function(){if(el.checked){theme=el.value;update();}});
    });
    root.querySelector("[data-pz-download]").addEventListener("click",async function(){
      var canvas=latest||await render(card,chosen.id,theme);await save(canvas,fileName(card,chosen.id,theme));
    });
    root.querySelector("[data-pz-all]").addEventListener("click",async function(){
      var btn=this;btn.disabled=true;btn.textContent="ZIP maken…";
      try{
        var entries=[];
        for(var f of formats){for(var t of ["light","dark"]){
          var c=await render(card,f.id,t),b=await new Promise(function(res){c.toBlob(res,"image/png");});
          if(b)entries.push({name:fileName(card,f.id,t),data:await b.arrayBuffer()});
        }}
        blobSave(zip(entries),"Pasr-"+String(card.name||"kaart").replace(/[^a-zA-Z0-9]+/g,"-")+"-Promotiemateriaal.zip");
      }finally{btn.disabled=false;btn.textContent="Download alle ontwerpen (ZIP)";}
    });
    if(options.print)root.querySelector("[data-pz-print]").addEventListener("click",function(){window.print();});
    update();
  }
  function escapeHTML(t){return String(t||"").replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];});}
  window.PasrPromo={mount:mount,render:render,formats:formats};
})();
