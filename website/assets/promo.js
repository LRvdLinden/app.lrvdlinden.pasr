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
  // Logo, tekst, kleur en stempels komen rechtstreeks uit de echte BusinessCard.
  function drawCard(ctx, card, x,y,w,h,imgs) {
    var base=color(card.color),ink=color(card.text_color,luminance(base)>.45?"#17162A":"#FFFFFF");
    if(!card.text_color)ink=luminance(base)>.45?"#17162A":"#FFFFFF";
    ctx.save();ctx.shadowColor="rgba(18,12,63,.24)";ctx.shadowBlur=29;ctx.shadowOffsetY=15;
    var bg=ctx.createLinearGradient(x,y,x+w,y+h);bg.addColorStop(0,mix(base,255,.16));
    bg.addColorStop(.56,base);bg.addColorStop(1,mix(base,0,.22));
    rr(ctx,x,y,w,h,Math.max(20,w*.048),bg);ctx.restore();
    var pad=w*.058;var logoS=Math.min(h*.18,w*.13);
    rr(ctx,x+pad,y+pad,logoS,logoS,logoS*.21,imgs.logo?"#FFFFFF":"rgba(255,255,255,.22)");
    if(imgs.logo){ctx.save();ctx.beginPath();ctx.roundRect(x+pad,y+pad,logoS,logoS,logoS*.2);ctx.clip();drawImg(ctx,imgs.logo,x+pad+4,y+pad+4,logoS-8,logoS-8);ctx.restore();}
    else text(ctx,(card.name||"P").slice(0,1).toUpperCase(),x+pad+logoS/2,y+pad+logoS*.69,"800 "+Math.round(logoS*.49)+"px Figtree, sans-serif",ink,"center");
    var titleX=x+pad+logoS+20,titleW=w-pad*2-logoS-25;
    var nameFont="800 "+Math.round(Math.min(w*.052,39))+"px 'Bricolage Grotesque',Figtree,sans-serif";
    text(ctx,card.name,titleX,y+pad+logoS*.42,nameFont,ink,"left",titleW);
    text(ctx,[card.business,card.city].filter(Boolean).join(" · "),titleX,y+pad+logoS*.79,
      "600 "+Math.round(Math.min(21,w*.026))+"px Figtree,sans-serif",ink,"left",titleW);
    var total=Math.min(30,Math.max(2,Number(card.stamps_total)||10));
    var cols=total<=5?total:total<=10?5:total<=12?6:total<=21?7:8;
    var rows=Math.ceil(total/cols),filled=Math.min(total-1,Math.max(1,Math.round(total*.4)));
    var availableH=h-logoS-pad*2-h*.23;
    var gridTop=y+pad+logoS+Math.max(12,h*.055);
    var gridBottom=gridTop+availableH;
    var cell=Math.min(w*.11,(w-pad*2-(cols-1)*12)/cols,(availableH-(rows-1)*10)/rows);
    var gapX=Math.min(14,(w-pad*2-cols*cell)/(cols-1||1));
    var gapY=rows>1?Math.min(11,(availableH-rows*cell)/(rows-1)):0;
    var gridW=cols*cell+(cols-1)*gapX,gridH=rows*cell+(rows-1)*gapY;
    var gx=x+(w-gridW)/2,gy=gridTop+(availableH-gridH)/2;
    for(var i=0;i<total;i++){
      var xx=gx+(i%cols)*(cell+gapX), yy=gy+Math.floor(i/cols)*(cell+gapY);
      if(i<filled){
        stampMark(ctx,imgs.stamp,xx,yy,cell,ink);
      } else {
        ctx.save();ctx.setLineDash([4,5]);ctx.strokeStyle=ink;ctx.globalAlpha=.65;
        ctx.lineWidth=2;ctx.beginPath();ctx.arc(xx+cell/2,yy+cell/2,cell*.43,0,2*Math.PI);ctx.stroke();ctx.restore();
      }
    }
    text(ctx,card.reward,x+pad,y+h-pad*.65,
      "700 "+Math.round(Math.min(24,w*.032))+"px Figtree,sans-serif",ink,"left",w*.65);
    text(ctx,total+" stempels",x+w-pad,y+h-pad*.65,
      "700 "+Math.round(Math.min(22,w*.029))+"px Figtree,sans-serif",ink,"right");
  }
  function background(ctx,w,h,dark) {
    var grad=ctx.createLinearGradient(0,0,w,h);
    if(dark){grad.addColorStop(0,"#17162A");grad.addColorStop(.6,"#252052");grad.addColorStop(1,"#37287D");}
    else{grad.addColorStop(0,"#FFFFFF");grad.addColorStop(.56,"#F4F3FF");grad.addColorStop(1,"#E7E2FF");}
    ctx.fillStyle=grad;ctx.fillRect(0,0,w,h);
    // Alleen bestaande Pasr-vormen: geen willekeurige AI-streepjes.
    ctx.fillStyle=dark?"rgba(106,92,255,.13)":"rgba(106,92,255,.08)";
    ctx.beginPath();ctx.arc(w*1.1,h*.05,w*.48,0,Math.PI*2);ctx.fill();
  }
  function drawLockup(ctx,icon,x,y,dark) {
    rr(ctx,x,y,74,74,17,"#17162A");drawImg(ctx,icon,x+2,y+2,70,70);
    text(ctx,"pasr",x+92,y+58,"800 71px 'Bricolage Grotesque',Figtree,sans-serif",dark?"#FFFFFF":"#17162A");
    rr(ctx,x+286,y+15,194,50,22,"#07966F");
    text(ctx,"ZAKELIJK",x+383,y+49,"800 27px Figtree,sans-serif","#FFFFFF","center");
  }
  async function render(card,formatId,theme) {
    var format=formats.find(function(f){return f.id===formatId;})||formats[0];
    var canvas=document.createElement("canvas");canvas.width=format.w;canvas.height=format.h;
    var ctx=canvas.getContext("2d",{alpha:false});var scale=format.w/1080,h=format.h/scale;
    ctx.scale(scale,scale);
    var imgs=await Promise.all([load(iconURL),load(stampURL),load(card.logo?
      "data:image/"+(card.logo.indexOf("/9j/")===0?"jpeg":"png")+";base64,"+card.logo:null)]);
    try{if(document.fonts&&document.fonts.ready)await document.fonts.ready;}catch(e){}
    var dark=theme==="dark",fg=dark?"#FFFFFF":"#17162A",muted=dark?"#C9C6E9":"#4B4966";
    background(ctx,1080,h,dark);
    var wide=format.id==="wide", isFlyer=format.id==="flyer";
    if(wide){
      ctx.save();ctx.scale(.55,.55);drawLockup(ctx,imgs[0],105,88,dark);ctx.restore();
      text(ctx,"Spaar digitaal bij",65,145,"800 65px 'Bricolage Grotesque',Figtree,sans-serif",fg);
      var n=wrap(ctx,card.business||card.name,440,"800 65px 'Bricolage Grotesque',Figtree,sans-serif",2);
      n.forEach(function(t,i){text(ctx,t,65,225+i*75,"800 65px 'Bricolage Grotesque',Figtree,sans-serif",dark?"#B9AAFF":"#4A3CE0");});
      text(ctx,"Scan en spaar mee met Pasr",65,480,"600 25px Figtree,sans-serif",muted);
      drawCard(ctx,card,565,110,465,293,{icon:imgs[0],stamp:imgs[1],logo:imgs[2]});
      if(card.published!==false)qrGrid(ctx,card.join_url||("https://pasr.nl/zakelijk/kaart/"+card.id+"/"),805,408,138);
    }else{
      drawLockup(ctx,imgs[0],76,75,dark);
      var headingY= h>1700?300:h>1250?260:225;
      text(ctx,"Spaar digitaal bij",76,headingY,"800 68px 'Bricolage Grotesque',Figtree,sans-serif",fg);
      var nameLines=wrap(ctx,card.business||card.name,940,"800 68px 'Bricolage Grotesque',Figtree,sans-serif",2);
      nameLines.forEach(function(t,i){text(ctx,t,76,headingY+86+i*80,"800 68px 'Bricolage Grotesque',Figtree,sans-serif",dark?"#B9AAFF":"#4A3CE0");});
      var cardW=900,cardH=567,cardY;
      if(isFlyer)cardY=Math.max(headingY+260,h*.29);
      else if(h>1700)cardY=650;
      else if(h>1250)cardY=515;
      else cardY=400;
      drawCard(ctx,card,90,cardY,cardW,cardH,{icon:imgs[0],stamp:imgs[1],logo:imgs[2]});
      var qrY=Math.min(h-290,cardY+cardH+58),qrS=Math.min(190,h-qrY-90);
      if(card.published!==false&&qrS>100){
        rr(ctx,90,qrY,900,qrS+35,28,dark?"#332A64":"#FFFFFF");
        qrGrid(ctx,card.join_url||("https://pasr.nl/zakelijk/kaart/"+card.id+"/"),114,qrY+17,qrS);
        text(ctx,"Scan en spaar mee",114+qrS+30,qrY+qrS*.55,
          "800 38px 'Bricolage Grotesque',Figtree,sans-serif",fg);
        text(ctx,"met Pasr",114+qrS+30,qrY+qrS*.84,"600 28px Figtree,sans-serif",muted);
      }else if(qrS>100){
        text(ctx,"Conceptkaart · publiceer voor een aanmeld-QR",96,qrY+44,"600 28px Figtree,sans-serif",muted);
      }
      if(isFlyer){
        text(ctx,"Scan de QR-code, bewaar de kaart en spaar bij elke aankoop.",
          90,h-105,"600 27px Figtree,sans-serif",fg,"left",900);
      }
    }
    return canvas;
  }
  function save(canvas,name){
    return new Promise(function(resolve){
      canvas.toBlob(function(blob){
        if(!blob)return resolve(null);
        var url=URL.createObjectURL(blob),a=document.createElement("a");
        a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();
        setTimeout(function(){URL.revokeObjectURL(url);},5000);resolve(blob);
      },"image/png");
    });
  }
  function fileName(card,format,theme){
    var safe=String(card.name||"stempelkaart").normalize("NFKD").replace(/[\u0300-\u036f]/g,"").replace(/[^a-zA-Z0-9]+/g,"-").replace(/^-|-$/g,"");
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
  function blobSave(blob,name){
    var url=URL.createObjectURL(blob),a=document.createElement("a");
    a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();
    setTimeout(function(){URL.revokeObjectURL(url);},5000);
  }
  function mount(root,card,options) {
    options=options||{};
    var chosen=formats[0],theme="light",latest=null,revision=0;
    root.innerHTML='<section class="pz-promo"><div class="pz-promo-heading"><h2>Promotiemateriaal · '+escapeHTML(card.name)+
      '</h2><p>Een banner van precies deze stempelkaart, met je eigen logo, kleur, beloning en QR-code.</p></div>'+
      '<div class="pz-promo-controls"><label>Formaat <select data-pz-format></select></label>'+
      '<fieldset><legend>Uitvoering</legend><label><input name="pz-theme" type="radio" value="light" checked> Licht</label>'+
      '<label><input name="pz-theme" type="radio" value="dark"> Donker</label></fieldset></div>'+
      '<div class="pz-promo-preview" aria-live="polite"><span data-pz-loading>Voorbeeld maken…</span><canvas data-pz-canvas></canvas></div>'+
      '<div class="pz-promo-actions"><button type="button" class="zk-btn" data-pz-download>Download PNG</button>'+
      '<button type="button" class="zk-btn ghost" data-pz-all>Download alle ontwerpen (ZIP)</button>'+
      (options.print?'<button type="button" class="zk-btn ghost" data-pz-print>Print A4/PDF</button>':"")+
      '</div><p class="pz-promo-note">De kaart is een promotiemodel, geen klantensaldo. Bij een conceptkaart verschijnt geen werkende QR-code.</p></section>';
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
