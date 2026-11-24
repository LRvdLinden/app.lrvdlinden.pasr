/* Pasr Zakelijk — loyaltyprogramma's, coupons en campagnes in de bestaande dashboardstijl.
 * Alle wijzigingen zijn per kaart en gaan alleen via eigenaar-geautoriseerde RPC's. */
(function(){
 "use strict";
 var $=function(s,r){return (r||document).querySelector(s);};
 var escape=function(v){return String(v==null?"":v).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];});};
 function el(tag,cls,txt){var e=document.createElement(tag);e.className=cls||"";if(txt!=null)e.textContent=txt;return e;}
 function notice(root,message,success){var n=$(".pz2-notice",root);if(n){n.textContent=message;n.dataset.ok=success?"true":"false";}}
 function field(label,name,value,type){return '<label class="pz2-field">'+escape(label)+'<input name="'+name+'" type="'+(type||"text")+'" value="'+escape(value||"")+'"></label>';}
 function jsonSafe(s){try{return JSON.parse(s||"{}");}catch(e){return null;}}
 function toggle(label,key,value,info){
   return '<label class="pz2-toggle"><span><b>'+escape(label)+'</b><small>'+escape(info)+'</small></span><input type="checkbox" name="'+key+'" '+(value?"checked":"")+'></label>';
 }
 function section(title,desc,content){
   return '<section class="pz2-panel"><h3>'+escape(title)+'</h3><p>'+escape(desc)+'</p>'+content+'</section>';
 }
 async function settingsView(root,b,rpc){
   var cards=b.cards||[];
   root.innerHTML='<div class="zd-ptitle"><div><h2>Acties en beloningen</h2><p class="zd-sub">Stel voordelen per echte stempelkaart in. Niets staat standaard aan.</p></div></div>'+
      (!cards.length?'<p>Maak eerst een stempelkaart.</p>':'<div class="pz2-controls"><label>Stempelkaart <select id="pz2Card">'+cards.map(function(c){return '<option value="'+escape(c.id)+'">'+escape(c.name)+'</option>';}).join("")+'</select></label></div>')+
      '<div id="pz2Settings"></div>';
   if(!cards.length)return;
   var select=$("#pz2Card",root);
   async function load(){
     var slot=$("#pz2Settings",root);slot.textContent="Instellingen laden…";
     var c=cards.find(function(x){return x.id===select.value;});
     try{
       var res=await rpc("pasr_business_program",{p_card:c.id},true);
       var cfg=res.settings||{},rs=cfg.rewards||[];
       slot.innerHTML='<form class="pz2-form" id="pz2Form">'+
         section("9. Meerdere beloningen","Mijlpalen zijn oplopend. Bij iedere mijlpaal bepaalt de ondernemer wat de klant krijgt.",
           toggle("Meerdere beloningen", "rewards_on",rs.length>0,"Een stempelkaart kan tot acht tussentijdse beloningen hebben.")+
           field("Mijlpalen: aantal stempels, dan een dubbele punt en de beloning (één per regel)","rewards_text","", "hidden")+
           '<label class="pz2-field">Beloningen (één per regel: 3: Gratis koekje)<textarea name="rewards" rows="4" placeholder="3: Gratis koekje&#10;6: Gratis upgrade">'+escape(rs.map(function(r){return r.stamps+": "+r.title;}).join("\n"))+'</textarea></label>')+
         section("10. Terugkomacties","De klant moet meldingen toestaan; er worden geen ongevraagde berichten verzonden.",
           toggle("Terugkomactie activeren","retention",cfg.retention&&cfg.retention.enabled,"Stel vast na hoeveel dagen zonder stempel een herinnering mag komen.")+
           field("Aantal dagen zonder bezoek","retention_days",(cfg.retention&&cfg.retention.days)||30,"number"))+
         section("11. Vrienden uitnodigen","De bonus wordt pas toegekend na een eerste, door de ondernemer geverifieerde aankoop.",
           toggle("Vrienden uitnodigen","referral",cfg.referral&&cfg.referral.enabled,"Eenmalig per nieuwe deelnemer. Zelfuitnodigingen tellen niet mee.")+
           '<details><summary>ⓘ Hoe werkt vrienden uitnodigen?</summary><p>De klant deelt een persoonlijke link. De nieuwe klant sluit zich aan. De server controleert de eerste geldige scan en kent daarna pas de bonus aan beide accounts toe. Een uitnodiging op zichzelf is geen beloning.</p></details>'+
           field("Bonus in stempels","referral_bonus",(cfg.referral&&cfg.referral.bonus)||1,"number"))+
         section("12. Tijdelijke stempelacties","Extra stempels, alleen binnen de ingestelde periode.",
           toggle("Tijdelijke actie","campaign",cfg.campaign&&cfg.campaign.enabled,"Bijvoorbeeld dubbele stempels op dinsdag.")+
           '<div class="pz2-fields">'+field("Vermenigvuldiger (1–3)","multiplier",(cfg.campaign&&cfg.campaign.multiplier)||2,"number")+
           field("Dag (0=zo t/m 6=za)","day",(cfg.campaign&&cfg.campaign.weekday)==null?2:cfg.campaign.weekday,"number")+'</div>')+
         section("13. Meerdere vestigingen","Alle vestigingen delen dezelfde kaart, maar rapportages blijven per vestiging.",
           toggle("Vestigingen beheren","locations",cfg.locations&&cfg.locations.enabled,"Bewaar hier de adresnamen; het uitgeven van stempels blijft aan bevoegd personeel.")+
           '<label class="pz2-field">Vestigingen (één per regel)<textarea name="locations_list" rows="3">'+escape(((cfg.locations&&cfg.locations.names)||[]).join("\n"))+'</textarea></label>')+
         section("14. VIP-niveaus","Brons, Zilver en Goud worden bepaald aan de hand van bezoeken.",
           toggle("VIP-niveaus","vip",cfg.vip&&cfg.vip.enabled,"Ondernemer bepaalt grenzen per kaart.")+
           '<div class="pz2-fields">'+field("Zilver vanaf bezoeken","silver",(cfg.vip&&cfg.vip.silver)||10,"number")+field("Goud vanaf bezoeken","gold",(cfg.vip&&cfg.vip.gold)||25,"number")+'</div>')+
         section("15. Marketingkalender","Plan een campagne en gebruik het bestaande promotiemateriaal voor socialmediabanners.",
           toggle("Marketingcampagne","marketing",cfg.marketing&&cfg.marketing.enabled,"Een conceptactie met begin- en einddatum.")+
           field("Campagnenaam","marketing_name",(cfg.marketing&&cfg.marketing.name)||""))+
         section("18. Winkelstraatacties","Deelnemende ondernemers moeten ieder afzonderlijk akkoord geven.",
           toggle("Interesse in gezamenlijke actie","community",cfg.community&&cfg.community.enabled,"Geen klantgegevens worden automatisch gedeeld.")+
           field("Naam van de gezamenlijke actie","community_name",(cfg.community&&cfg.community.name)||""))+
         '<p class="pz2-notice" role="status"></p><button class="zk-btn" type="submit">Instellingen van deze kaart opslaan</button></form>';
       var form=$("#pz2Form",slot);
       form.addEventListener("submit",async function(e){
         e.preventDefault();var f=new FormData(form);
         function yes(n){return f.has(n);}
         function num(n,d){return Number(f.get(n)||d);}
         var rewards=[];
         if(yes("rewards_on")){
           var lines=String(f.get("rewards")||"").split(/\r?\n/).filter(Boolean);
           for(var line of lines){var m=line.match(/^\s*(\d+)\s*:\s*(.{3,80})\s*$/);if(!m){notice(slot,"Gebruik het formaat ‘3: Gratis koekje’.",false);return;}
             rewards.push({stamps:+m[1],title:m[2].trim()});}
           rewards.sort(function(a,b){return a.stamps-b.stamps;});
         }
         var settings={
           rewards:rewards,
           retention:{enabled:yes("retention"),days:num("retention_days",30)},
           referral:{enabled:yes("referral"),bonus:num("referral_bonus",1)},
           campaign:{enabled:yes("campaign"),multiplier:num("multiplier",2),weekday:num("day",2)},
           locations:{enabled:yes("locations"),names:String(f.get("locations_list")||"").split(/\r?\n/).map(function(x){return x.trim();}).filter(Boolean).slice(0,20)},
           vip:{enabled:yes("vip"),silver:num("silver",10),gold:num("gold",25)},
           marketing:{enabled:yes("marketing"),name:String(f.get("marketing_name")||"").slice(0,80)},
           community:{enabled:yes("community"),name:String(f.get("community_name")||"").slice(0,80)}
         };
         if(settings.referral.bonus<1||settings.referral.bonus>3||settings.retention.days<7||settings.retention.days>365||
            settings.campaign.multiplier<1||settings.campaign.multiplier>3||settings.campaign.weekday<0||settings.campaign.weekday>6||
            settings.vip.silver<1||settings.vip.gold<=settings.vip.silver){
            notice(slot,"Controleer bonus, dagen, vermenigvuldiger en VIP-grenzen.",false);return;
         }
         var button=form.querySelector('button[type="submit"]');button.disabled=true;
         try{await rpc("pasr_business_program",{p_card:c.id,p_settings:settings},true);
           notice(slot,"Instellingen opgeslagen. Optionele serverregels kunnen pas worden uitgevoerd zodra de campagneverwerking actief is.",true);
         }catch(err){notice(slot,err.message||"Opslaan mislukt.",false);}finally{button.disabled=false;}
       });
     }catch(e){slot.textContent="Kon instellingen niet laden: "+(e.message||"onbekend");}
   }
   select.addEventListener("change",load);load();
 }
 function money(type,val){return type==="percent"?val+"%":new Intl.NumberFormat("nl-NL",{style:"currency",currency:"EUR"}).format(val);}
 async function couponDashboard(root,b,rpc){
   root.innerHTML='<div class="zd-ptitle"><div><h2>Kortingsbonnen</h2><p class="zd-sub">Maak een tijdelijke kortingsbon met een uniek te verzilveren QR- of tekstcode.</p></div></div>'+
    '<div class="pz2-grid"><form class="pz2-panel pz2-form" id="pz2Coupon">'+
      '<h3>Nieuwe kortingsbon</h3>'+
      field("Titel","title","Korting op je volgende aankoop")+
      field("Omschrijving","description","Alleen in de winkel")+
      '<label class="pz2-field">Korting <select name="discount_type"><option value="amount">Vast bedrag (€)</option><option value="percent">Percentage (%)</option></select></label>'+
      '<div class="pz2-fields">'+field("Korting","discount_value","2.50","number")+field("Minimale besteding (€)","min_spend","10","number")+'</div>'+
      '<div class="pz2-fields">'+field("Startdatum","starts_at",new Date().toISOString().slice(0,10),"date")+
      field("Einddatum","ends_at",new Date(Date.now()+30*86400000).toISOString().slice(0,10),"date")+'</div>'+
      field("Maximaal aantal uitgiftes","max_claims","500","number")+
      '<label class="pz2-toggle"><span><b>Eenmalig per klant</b><small>Voorkom herhaald claimen</small></span><input name="one_per_customer" type="checkbox" checked></label>'+
      '<label class="pz2-toggle"><span><b>Publiceer in Pasr</b><small>Pas na publiceren en de startdatum zichtbaar</small></span><input name="public" type="checkbox"></label>'+
      '<p class="pz2-notice" role="status"></p><button type="submit" class="zk-btn">Kortingsbon maken</button></form>'+
      '<section class="pz2-panel"><h3>Jouw kortingsbonnen</h3><div id="pz2Coupons">Laden…</div>'+
      '<p>Klanten bewaren de bon in Pasr en krijgen een unieke code. Alleen je eigen team kan die code inwisselen.</p></section></div>'+
      '<section class="pz2-panel"><h3>Bon aan de kassa verzilveren</h3><div class="pz2-inline">'+
      '<label class="pz2-field">PC-code <input id="pz2RedeemCode" maxlength="24" placeholder="PC…"></label>'+
      '<button class="zk-btn" id="pz2Redeem" type="button">Controleer en verzilver</button></div><p id="pz2RedeemMessage" role="status"></p></section>';
   async function reload(){try{
       var rows=await rpc("pasr_business_coupon_list",{p_business:b.id},true);
       $("#pz2Coupons",root).innerHTML=rows.length?rows.map(function(c){return '<article class="pz2-coupon"><b>'+escape(c.title)+'</b> · '+
         money(c.discount_type,c.discount_value)+'<br><small>'+escape(new Date(c.ends_at).toLocaleDateString("nl-NL"))+
         ' · '+c.claimed+' opgehaald · '+c.redeemed+' gebruikt · '+(c.public?"Gepubliceerd":"Concept")+'</small></article>';}).join(""):"Nog geen kortingsbonnen.";
     }catch(e){$("#pz2Coupons",root).textContent="Kon kortingsbonnen niet laden: "+(e.message||"onbekend");}
   }
   $("#pz2Coupon",root).addEventListener("submit",async function(e){
     e.preventDefault();var f=new FormData(this),button=this.querySelector("button[type=submit]");button.disabled=true;
     try{var payload={business_id:b.id,title:f.get("title"),description:f.get("description"),discount_type:f.get("discount_type"),
       discount_value:Number(f.get("discount_value")),min_spend:Number(f.get("min_spend")),starts_at:f.get("starts_at")+"T00:00:00+01:00",
       ends_at:f.get("ends_at")+"T23:59:59+01:00",max_claims:Number(f.get("max_claims")),
       one_per_customer:f.has("one_per_customer"),public:f.has("public")};
       await rpc("pasr_business_coupon_save",{p_coupon:payload},true);notice(root,"Kortingsbon opgeslagen.",true);reload();
     }catch(err){notice(root,err.message||"Opslaan mislukt.",false);}finally{button.disabled=false;}
   });
   $("#pz2Redeem",root).addEventListener("click",async function(){var msg=$("#pz2RedeemMessage",root);
     if(!window.confirm("Controleer bij de kassa of je de korting daadwerkelijk wilt geven. Deze bon wordt definitief als gebruikt gemarkeerd."))return;
     try{var x=await rpc("pasr_business_coupon_redeem",{p_code:$("#pz2RedeemCode",root).value},true);
       msg.textContent="Geldig: "+x.title+" · korting "+money(x.discount_type,x.discount_value)+". Bon verzilverd.";reload();
     }catch(e){msg.textContent=e.message||"Niet geldig.";}
   });
   reload();
 }
 function publicPage(root){
   var cfg=window.PASR_ACCOUNT||{},ready=!!(cfg.url&&cfg.key);
   root.innerHTML='<div class="pz2-hero"><span class="zk-kicker">Pasr · Klantenkaarten</span><h1>Kortingsbonnen</h1><p>Ontdek tijdelijke aanbiedingen van ondernemers in Pasr. Bewaar een bon in je account en laat je code bij de ondernemer scannen.</p></div>'+
    '<div class="pz2-controls"><input id="pz2Search" aria-label="Zoeken" placeholder="Zoek winkel of aanbieding"></div><div id="pz2PublicList" class="pz2-grid"><p>Acties laden…</p></div>';
   if(!ready){$("#pz2PublicList",root).textContent="Aanbiedingen zijn tijdelijk niet beschikbaar.";return;}
   var rows=[];
   async function rpcPublic(fn,payload,access){
     var response=await fetch(cfg.url.replace(/\/$/,"")+"/rest/v1/rpc/"+fn,{method:"POST",headers:{"Content-Type":"application/json","apikey":cfg.key,"Authorization":"Bearer "+(access||cfg.key)},body:JSON.stringify(payload||{})});
     var data=await response.json();if(!response.ok)throw new Error(data.message||"Verbinding mislukt.");return data;
   }
   function show(){
     var q=$("#pz2Search",root).value.toLowerCase();
     $("#pz2PublicList",root).innerHTML=rows.filter(function(c){return (c.business+" "+c.title).toLowerCase().includes(q);})
     .map(function(c){return '<article class="pz2-publiccard"><div class="pz2-violet"><small>'+escape(c.business)+'</small>'+
       '<strong>'+money(c.discount_type,c.discount_value)+' korting</strong></div><div class="pz2-publicbody"><h2>'+escape(c.title)+'</h2><p>'+escape(c.description)+'</p>'+
       '<small>Vanaf € '+escape(c.min_spend)+' · geldig tot '+escape(new Date(c.ends_at).toLocaleDateString("nl-NL"))+'</small>'+
       '<button class="zk-btn" type="button" data-coupon="'+escape(c.id)+'">Bewaar kortingsbon</button></div></article>';}).join("")||
       '<p>Er zijn momenteel geen beschikbare kortingsbonnen.</p>';
     root.querySelectorAll("[data-coupon]").forEach(function(button){button.addEventListener("click",function(){claim(button.dataset.coupon);});});
   }
   // Bij webgebruik een normale Pasr-accountlogin; native apps gebruiken hun bestaande sessie.
   var couponSessionKey="pasr.coupons.session";
   var pendingCoupon=null;
   function couponSession(){try{
     var s=JSON.parse(sessionStorage.getItem(couponSessionKey)||"null");
     if(s&&s.token&&s.until>Date.now()+60000)return s;
   }catch(e){}return null;}
   function loginForCoupon(id){
     pendingCoupon=id;
     var modal=el("div","pz2-dialog");
     modal.innerHTML='<form class="pz2-panel pz2-form" aria-label="Log in bij Pasr" id="pz2Login">'+
       '<h2>Log in bij Pasr</h2><p>Om een persoonlijke kortingsbon te bewaren, heb je een gratis Pasr-account nodig.</p>'+
       '<label class="pz2-field">E-mailadres<input type="email" name="email" required autocomplete="email"></label>'+
       '<label class="pz2-field">Wachtwoord<input type="password" name="password" required autocomplete="current-password"></label>'+
       '<p role="status" class="pz2-notice"></p><button class="zk-btn" type="submit">Inloggen en bewaren</button>'+
       '<button class="zk-btn ghost" type="button" data-close>Annuleren</button><a href="/account/">Nog geen account?</a></form>';
     document.body.appendChild(modal);
     modal.querySelector("[data-close]").addEventListener("click",function(){modal.remove();});
     $("#pz2Login",modal).addEventListener("submit",async function(e){
       e.preventDefault();var form=this,button=form.querySelector('button[type=submit]');button.disabled=true;
       try{
         var res=await fetch(cfg.url.replace(/\/$/,"")+"/auth/v1/token?grant_type=password",{
           method:"POST",headers:{"Content-Type":"application/json","apikey":cfg.key},
           body:JSON.stringify({email:form.elements.email.value.trim(),password:form.elements.password.value})
         });
         var data=await res.json();if(!res.ok||!data.access_token)throw Error("Inloggen mislukt. Controleer je e-mailadres en wachtwoord.");
         sessionStorage.setItem(couponSessionKey,JSON.stringify({token:data.access_token,until:Date.now()+(data.expires_in||3600)*1000}));
         modal.remove();if(id)claim(id);else myCoupons();
       }catch(e){notice(modal,e.message||"Inloggen mislukt.",false);button.disabled=false;}
     });
   }
   function showClaim(c,customerTitle){
     var modal=el("div","pz2-dialog");
     modal.innerHTML='<div role="dialog" aria-modal="true" aria-label="Jouw kortingsbon" class="pz2-panel"><h2>Jouw kortingsbon</h2>'+
       '<p>'+escape(customerTitle||"Toon deze unieke code aan de ondernemer.")+'</p>'+
       '<div class="pz2-qr" id="pz2ClaimQR"></div>'+
       '<p class="pz2-code">'+escape(c.code)+'</p><button class="zk-btn" type="button">Sluiten</button></div>';
     document.body.appendChild(modal);
     if(typeof qrcode==="function"){var qr=qrcode(0,"M");qr.addData(c.code);qr.make();
       $("#pz2ClaimQR",modal).innerHTML=qr.createSvgTag({cellSize:5,margin:2,scalable:true});}
     modal.querySelector("button").addEventListener("click",function(){modal.remove();});
   }
   async function claim(id){
     var sess=couponSession();if(!sess){loginForCoupon(id);return;}
     try{var c=await rpcPublic("pasr_business_coupon_claim",{p_coupon:id},sess.token);
       showClaim(c,"Toon de unieke QR-code bij de kassa. Alleen de ondernemer kan de bon verzilveren.");
     }catch(e){alert(e.message||"Bewaren mislukt.");}
   }
   async function myCoupons(){
     var sess=couponSession();if(!sess){loginForCoupon(null);return;}
     try{
       var list=await rpcPublic("pasr_business_coupon_mine",{},sess.token);
       var modal=el("div","pz2-dialog");
       modal.innerHTML='<div role="dialog" aria-modal="true" aria-label="Mijn kortingsbonnen" class="pz2-panel"><h2>Mijn kortingsbonnen</h2>'+
         '<div id="pz2Mine"></div><button class="zk-btn ghost" type="button" data-close>Sluiten</button></div>';
       document.body.appendChild(modal);
       $("#pz2Mine",modal).innerHTML=list.length?list.map(function(c,i){return '<button type="button" class="zk-btn ghost" data-idx="'+i+'">'+
         escape(c.business)+" · "+escape(c.title)+(c.redeemed?" (Gebruikt)":"")+'</button>';}).join(""):'<p>Je hebt nog geen kortingsbonnen bewaard.</p>';
       modal.querySelectorAll("[data-idx]").forEach(function(b){b.addEventListener("click",function(){
         var c=list[Number(b.dataset.idx)];if(c.redeemed)return;modal.remove();showClaim(c,c.title);
       });});
       modal.querySelector("[data-close]").addEventListener("click",function(){modal.remove();});
     }catch(e){alert(e.message||"Kon bonnen niet ophalen.");}
   }
   var mineButton=document.createElement("button");mineButton.className="zk-btn ghost";
   mineButton.textContent="Mijn kortingsbonnen";mineButton.type="button";
   $(".pz2-controls",root).appendChild(mineButton);mineButton.addEventListener("click",myCoupons);
   $("#pz2Search",root).addEventListener("input",show);
   rpcPublic("pasr_business_coupon_list",{}).then(function(r){rows=Array.isArray(r)?r:[];show();})
     .catch(function(){$("#pz2PublicList",root).textContent="De aanbiedingen konden niet worden opgehaald.";});
 }
 async function insightsView(root,b,rpc){
   root.innerHTML='<div class="zd-ptitle"><div><h2>Bedrijfsinzichten</h2><p class="zd-sub">Geaggregeerde gegevens van jouw stempelkaarten en kortingsbonnen. Er worden geen klantnamen of contactgegevens getoond.</p></div></div>'+
     '<div id="pz2Stats" class="pz2-statgrid" aria-live="polite"><p>Inzichten laden…</p></div>'+
     '<section class="pz2-panel"><h3>Hoe lees je deze cijfers?</h3>'+
     '<p>De cijfers zijn gebaseerd op echte scans en geregistreerde inwisselingen. Een terugkerende klant heeft minimaal twee stempels ontvangen in de afgelopen 90 dagen. Deze cijfers zijn geen omzetmeting.</p>'+
     '<p>Een ondernemer ziet uitsluitend zijn eigen gegevens. Er worden geen volledige klantcodes of persoonlijke gegevens gedeeld.</p></section>';
   try{
     var x=await rpc("pasr_business_loyalty_insights",{p_business:b.id},true);
     var stats=[
       ["Klanten",x.members,"Houders van je zakelijke stempelkaarten"],
       ["Nieuwe klanten (30 dagen)",x.members_30d,"Ingeschreven in de laatste 30 dagen"],
       ["Stempels (30 dagen)",x.stamps_30d,"Aantal geldige stempels in de laatste 30 dagen"],
       ["Terugkerende klanten (90 dagen)",x.returning_customers_90d,"Minimaal twee geregistreerde stempelacties"],
       ["Tussentijdse beloningen",x.milestone_rewards,"Door de ondernemer uitgegeven"],
       ["Kortingsbonnen bewaard",x.claimed_coupons,"Persoonlijke boncodes uitgegeven"],
       ["Kortingsbonnen gebruikt",x.redeemed_coupons,"Aan de kassa ingewisseld"]
     ];
     $("#pz2Stats",root).innerHTML=stats.map(function(item){return '<article class="pz2-stat"><strong>'+
       new Intl.NumberFormat("nl-NL").format(Number(item[1]||0))+'</strong><b>'+escape(item[0])+'</b><small>'+
       escape(item[2])+'</small></article>';}).join("");
   }catch(e){$("#pz2Stats",root).textContent="De inzichten konden niet worden geladen: "+(e.message||"onbekend");}
 }
 window.PasrLoyalty2={settings:settingsView,coupons:couponDashboard,insights:insightsView,publicPage:publicPage};
})();
