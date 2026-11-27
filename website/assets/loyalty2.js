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
           field("Actiedag (-1=elke dag, 0=zo t/m 6=za)","day",(cfg.campaign&&cfg.campaign.weekday)==null?2:cfg.campaign.weekday,"number")+
           field("Startdatum","campaign_start",(cfg.campaign&&cfg.campaign.start)||new Date().toLocaleDateString("en-CA"),"date")+
           field("Einddatum","campaign_end",(cfg.campaign&&cfg.campaign.end)||new Date(Date.now()+30*86400000).toLocaleDateString("en-CA"),"date")+'</div>')+
         section("13. Meerdere vestigingen","Alle vestigingen delen dezelfde kaart, maar rapportages blijven per vestiging.",
           toggle("Vestigingen beheren","locations",cfg.locations&&cfg.locations.enabled,"Bewaar hier de adresnamen; het uitgeven van stempels blijft aan bevoegd personeel.")+
           '<label class="pz2-field">Vestigingen (één per regel)<textarea name="locations_list" rows="3">'+escape(((cfg.locations&&cfg.locations.names)||[]).join("\n"))+'</textarea></label>')+
         section("14. VIP-niveaus","Brons, Zilver en Goud worden bepaald aan de hand van bezoeken.",
           toggle("VIP-niveaus","vip",cfg.vip&&cfg.vip.enabled,"Ondernemer bepaalt grenzen per kaart.")+
           '<div class="pz2-fields">'+field("Zilver vanaf bezoeken","silver",(cfg.vip&&cfg.vip.silver)||10,"number")+field("Goud vanaf bezoeken","gold",(cfg.vip&&cfg.vip.gold)||25,"number")+'</div>'+
           '<div class="pz2-fields">'+field("Voordeel bij zilver (optioneel)","vip_silver_benefit",(cfg.vip&&cfg.vip.silver_benefit)||"")+
           field("Voordeel bij goud (optioneel)","vip_gold_benefit",(cfg.vip&&cfg.vip.gold_benefit)||"")+'</div>')+
         section("15. Marketingkalender","Plan een campagne en gebruik het bestaande promotiemateriaal voor socialmediabanners.",
           toggle("Marketingcampagne","marketing",cfg.marketing&&cfg.marketing.enabled,"Een conceptactie met begin- en einddatum.")+
           field("Campagnenaam","marketing_name",(cfg.marketing&&cfg.marketing.name)||""))+
         section("18. Winkelstraatacties","Deelnemende ondernemers moeten ieder afzonderlijk akkoord geven.",
           toggle("Interesse in gezamenlijke actie","community",cfg.community&&cfg.community.enabled,"Dit is een voorkeur. Maak een echte actie aan op het tabblad Samenwerkingen.")+
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
           campaign:{enabled:yes("campaign"),multiplier:num("multiplier",2),weekday:num("day",2),
             start:String(f.get("campaign_start")||""),end:String(f.get("campaign_end")||"")},
           locations:{enabled:yes("locations"),names:String(f.get("locations_list")||"").split(/\r?\n/).map(function(x){return x.trim();}).filter(Boolean).slice(0,20)},
           vip:{enabled:yes("vip"),silver:num("silver",10),gold:num("gold",25),
             silver_benefit:String(f.get("vip_silver_benefit")||"").trim().slice(0,120),
             gold_benefit:String(f.get("vip_gold_benefit")||"").trim().slice(0,120)},
           marketing:{enabled:yes("marketing"),name:String(f.get("marketing_name")||"").slice(0,80)},
           community:{enabled:yes("community"),name:String(f.get("community_name")||"").slice(0,80)}
         };
         if(settings.referral.bonus<1||settings.referral.bonus>3||settings.retention.days<7||settings.retention.days>365||
            settings.campaign.multiplier<1||settings.campaign.multiplier>3||settings.campaign.weekday<-1||settings.campaign.weekday>6||
            (settings.campaign.enabled && (!/^20\d{2}-\d{2}-\d{2}$/.test(settings.campaign.start)||
             !/^20\d{2}-\d{2}-\d{2}$/.test(settings.campaign.end)||settings.campaign.end<settings.campaign.start))||
            settings.vip.silver<1||settings.vip.gold<=settings.vip.silver){
            notice(slot,"Controleer bonus, dagen, vermenigvuldiger en VIP-grenzen.",false);return;
         }
         var button=form.querySelector('button[type="submit"]');button.disabled=true;
         try{await rpc("pasr_business_program",{p_card:c.id,p_settings:settings},true);
           notice(slot,"Instellingen van deze kaart opgeslagen.",true);
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
      '<h3 id="pz2CouponHeading">Nieuwe kortingsbon</h3>'+
      field("Titel","title","Korting op je volgende aankoop")+
      field("Omschrijving","description","Alleen in de winkel")+
      '<label class="pz2-field">Korting <select name="discount_type"><option value="amount">Vast bedrag (€)</option><option value="percent">Percentage (%)</option></select></label>'+
      '<div class="pz2-fields">'+field("Korting","discount_value","2.50","number")+field("Minimale besteding (€)","min_spend","10","number")+'</div>'+
      '<div class="pz2-fields">'+field("Startdatum","starts_at",new Date().toISOString().slice(0,10),"date")+
      field("Einddatum","ends_at",new Date(Date.now()+30*86400000).toISOString().slice(0,10),"date")+'</div>'+
      field("Maximaal aantal uitgiftes","max_claims","500","number")+
      '<label class="pz2-toggle"><span><b>Eenmalig per klant</b><small>Voorkom herhaald claimen</small></span><input name="one_per_customer" type="checkbox" checked></label>'+
      '<label class="pz2-toggle"><span><b>Publiceer in Pasr</b><small>Pas na publiceren en de startdatum zichtbaar</small></span><input name="public" type="checkbox"></label>'+
      '<p class="pz2-notice" role="status"></p><button type="submit" class="zk-btn">Kortingsbon opslaan</button><button type="button" class="zk-btn ghost" id="pz2CouponReset">Nieuw</button></form>'+
      '<section class="pz2-panel"><h3>Jouw kortingsbonnen</h3><div id="pz2Coupons">Laden…</div>'+
      '<p>Klanten bewaren de bon in Pasr en krijgen een unieke code. Alleen je eigen team kan die code inwisselen.</p></section></div>'+
      '<section class="pz2-panel"><h3>Bon aan de kassa verzilveren</h3><div class="pz2-inline">'+
      '<label class="pz2-field">PC-code <input id="pz2RedeemCode" maxlength="24" placeholder="PC…"></label>'+
      '<button class="zk-btn" id="pz2Redeem" type="button">Controleer en verzilver</button></div><p id="pz2RedeemMessage" role="status"></p></section>';
   var editingID=null, allCoupons=[];
   async function reload(){try{
       var rows=await rpc("pasr_business_coupon_list",{p_business:b.id},true);
       rows=(rows||[]).filter(function(row){return !row.deleted;});
       allCoupons=rows;
       $("#pz2Coupons",root).innerHTML=rows.length?rows.map(function(c,i){return '<article class="pz2-coupon"><b>'+escape(c.title)+'</b> · '+
         money(c.discount_type,c.discount_value)+'<br><small>'+escape(new Date(c.ends_at).toLocaleDateString("nl-NL"))+
         ' · '+c.claimed+' opgehaald · '+c.redeemed+' gebruikt · '+(c.deleted?"Verwijderd":c.public?"Actief":"Gepauzeerd")+'</small>'+
         (!c.deleted?'<div class="zk-actions"><button type="button" class="zk-btn ghost" data-editcoupon="'+i+'">Bewerken</button>'+
         '<button type="button" class="zk-btn ghost" data-removecoupon="'+i+'">Verwijderen</button></div>':'')+
         '</article>';}).join(""):"Nog geen kortingsbonnen.";
       root.querySelectorAll("[data-editcoupon]").forEach(function(btn){btn.addEventListener("click",function(){
          var c=allCoupons[Number(btn.dataset.editcoupon)],form=$("#pz2Coupon",root);
          editingID=c.id;
          ["title","description","discount_type","discount_value","min_spend","max_claims"].forEach(function(k){
            form.elements[k].value=c[k]||"";
          });
          form.elements.starts_at.value=String(c.starts_at||"").slice(0,10);
          form.elements.ends_at.value=String(c.ends_at||"").slice(0,10);
          form.elements.one_per_customer.checked=!!c.one_per_customer;
          form.elements.public.checked=!!c.public;
          $("#pz2CouponHeading",root).textContent="Kortingsbon bewerken · "+c.title;
          form.scrollIntoView({behavior:"smooth",block:"start"});
       });});
       root.querySelectorAll("[data-removecoupon]").forEach(function(btn){btn.addEventListener("click",async function(){
          var c=allCoupons[Number(btn.dataset.removecoupon)];
          if(!window.confirm("Verwijder "+c.title+"? De actie wordt onbruikbaar, eerdere verzilveringen blijven bewaard."))return;
          btn.disabled=true;
          try{await rpc("pasr_business_discount_remove",{p_business:b.id,p_id:c.id,p_kind:"coupon"},true);
            notice(root,"Kortingsbon verwijderd; historie behouden.",true);if(editingID===c.id)editingID=null;await reload();
          }catch(e){notice(root,e.message||"Verwijderen mislukt.",false);btn.disabled=false;}
       });});
     }catch(e){$("#pz2Coupons",root).textContent="Kon kortingsbonnen niet laden: "+(e.message||"onbekend");}
   }
   $("#pz2Coupon",root).addEventListener("submit",async function(e){
     e.preventDefault();var f=new FormData(this),button=this.querySelector("button[type=submit]");button.disabled=true;
     try{var payload={business_id:b.id,title:f.get("title"),description:f.get("description"),discount_type:f.get("discount_type"),
       discount_value:Number(f.get("discount_value")),min_spend:Number(f.get("min_spend")),starts_at:f.get("starts_at")+"T00:00:00+01:00",
       ends_at:f.get("ends_at")+"T23:59:59+01:00",max_claims:Number(f.get("max_claims")),
       one_per_customer:f.has("one_per_customer"),public:f.has("public")};
       if(editingID)payload.id=editingID;
       await rpc("pasr_business_coupon_save",{p_coupon:payload},true);
       notice(root,"Kortingsbon opgeslagen.",true);editingID=null;
       $("#pz2CouponHeading",root).textContent="Nieuwe kortingsbon";reload();
     }catch(err){notice(root,err.message||"Opslaan mislukt.",false);}finally{button.disabled=false;}
   });
   $("#pz2CouponReset",root).addEventListener("click",function(){
     editingID=null;$("#pz2Coupon",root).reset();
     $("#pz2CouponHeading",root).textContent="Nieuwe kortingsbon";
   });
   $("#pz2Redeem",root).addEventListener("click",async function(){var msg=$("#pz2RedeemMessage",root);
     var code=$("#pz2RedeemCode",root).value.trim().toUpperCase();
     if(!code){msg.textContent="Vul eerst de kortingsboncode in.";return;}
     try{
       var check=await rpc("pasr_business_coupon_check",{p_code:code},true);
       if(!check||check.valid===false||check.ok===false){
         msg.textContent=(check&&check.reason)||"De bon is ongeldig.";return;
       }
       if(!window.confirm("Kortingsbon "+(check.title||code)+" definitief verzilveren?"))return;
       var x=await rpc("pasr_business_coupon_redeem",{p_code:code},true);
       msg.textContent="Geldig: "+x.title+" · korting "+money(x.discount_type,x.discount_value)+". Bon verzilverd.";reload();
     }catch(e){msg.textContent=e.message||"Niet geldig.";}
   });
   reload();
 }
 function publicPage(root){
   var cfg=window.PASR_ACCOUNT||{}, ready=!!(cfg.url&&cfg.key);
   root.innerHTML='<div class="pz2-hero"><span class="zk-kicker">Pasr · Klantenkaarten</span>'+
     '<h1>Exclusieve Pasr-acties</h1><p>Bekijk kortingscoupons en actiecodes van lokale ondernemers. Bewaren, een QR-code tonen en verzilveren kan uitsluitend in de Pasr: Klantenkaarten-app.</p></div>'+
     '<div class="pz2-controls"><input id="pz2Search" aria-label="Zoek acties" placeholder="Zoek winkel of aanbieding"></div>'+
     '<div class="pz2-grid" id="pz2PublicList"><p>Acties laden…</p></div>';
   var box=$("#pz2PublicList",root),search=$("#pz2Search",root), rows=[];
   var ios="https://apps.apple.com/nl/app/pasr-klantenkaarten/id6829229123";
   function show(){
     var q=search.value.toLowerCase();
     box.innerHTML=rows.filter(function(x){return (x.business+" "+x.title).toLowerCase().includes(q);})
       .map(function(c){
         var isCode=c.kind==="code",discount=money(c.discount_type,c.discount_value);
         var raw=c.logo||"",logo=/^[A-Za-z0-9+/=]+$/.test(raw)&&raw.length<220000?
           '<img alt="Bedrijfslogo" style="width:44px;height:44px;object-fit:contain;background:#fff;border-radius:9px" src="data:image/'+(raw.indexOf("/9j/")===0?"jpeg":"png")+';base64,'+raw+'">':
           '<span aria-hidden="true" style="font-size:25px">🏬</span>';
         var base=/^#[0-9a-f]{6}$/i.test(c.color||"")?c.color:"#6A5CFF";
         return '<article class="pz2-publiccard"><div class="pz2-violet" style="background:'+base+';border-radius:20px;padding:22px;color:#fff">'+
           '<div style="display:flex;align-items:center;justify-content:space-between;gap:12px">'+
           logo+'<strong style="margin-left:auto;font-size:22px">pasr.</strong></div>'+
           '<small>'+escape(c.business)+'</small><strong style="font-size:30px">'+escape(discount)+' KORTING</strong>'+
           '<p>'+escape(c.title)+'</p><span>🔒 '+(isCode?"Actiecode":"Kortingscoupon")+' uitsluitend in Pasr</span></div>'+
           '<div class="pz2-publicbody"><p>Deze aanbieding is alleen te gebruiken in de Pasr: Klantenkaarten-app.</p>'+
           '<small>Geldig t/m '+escape(new Date(c.ends_at).toLocaleDateString("nl-NL"))+'</small>'+
           '<p><a class="zk-btn" href="'+ios+'" rel="noopener">Open in Pasr</a></p></div></article>';
       }).join("")||'<p>Er zijn momenteel geen beschikbare aanbiedingen.</p>';
   }
   search.addEventListener("input",show);
   if(!ready){box.textContent="Aanbiedingen zijn tijdelijk niet beschikbaar.";return;}
   async function publicRPC(fn){
     var response=await fetch(cfg.url.replace(/\/$/,"")+"/rest/v1/rpc/"+fn,{
       method:"POST",headers:{"Content-Type":"application/json","apikey":cfg.key,
         "Authorization":"Bearer "+cfg.key},body:"{}"});
     var data=await response.json();
     if(!response.ok)throw new Error(data.message||"Aanbiedingen laden mislukt");
     return Array.isArray(data)?data:[];
   }
   Promise.allSettled([publicRPC("pasr_business_coupon_list"),publicRPC("pasr_business_promo_public")])
     .then(function(results){
       rows=[];
       if(results[0].status==="fulfilled")rows=rows.concat(results[0].value.map(function(x){x.kind="coupon";return x;}));
       if(results[1].status==="fulfilled")rows=rows.concat(results[1].value.map(function(x){x.kind="code";return x;}));
       if(results.every(function(r){return r.status==="rejected";})){
         box.textContent="Aanbiedingen konden niet worden geladen.";return;
       }
       show();
     });
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

 async function marketingView(root,b,rpc){
  var cards=b.cards||[];
  root.innerHTML='<div class="zd-ptitle"><div><h2>Marketingkalender</h2><p class="zd-sub">Plan acties per kaart en maak er promotiemateriaal bij. Berichten worden niet automatisch verzonden.</p></div></div>'+
   '<div class="pz2-grid"><section class="pz2-panel"><h3>Campagne plannen</h3><form class="pz2-form" id="pz2Marketing">'+
   field("Campagnenaam","title","")+
   '<label class="pz2-field">Stempelkaart <select name="card_id"><option value="">Algemene actie</option>'+
   cards.map(function(c){return '<option value="'+escape(c.id)+'">'+escape(c.name)+'</option>';}).join("")+'</select></label>'+
   '<div class="pz2-fields">'+field("Start","starts_on",new Date().toISOString().slice(0,10),"date")+
   field("Einde","ends_on",new Date(Date.now()+7*86400000).toISOString().slice(0,10),"date")+'</div>'+
   '<label class="pz2-field">Kanaal <select name="channel"><option value="social">Social</option><option value="winkel">Winkel</option><option value="web">Website</option><option value="email">E-mail (handmatig)</option></select></label>'+
   '<label class="pz2-field">Status <select name="status"><option value="draft">Concept</option><option value="planned" selected>Gepland</option><option value="completed">Afgerond</option></select></label>'+
   '<label class="pz2-field">Omschrijving<textarea name="details" maxlength="600" rows="3"></textarea></label>'+
   '<p class="pz2-notice" role="status"></p><button type="submit" class="zk-btn">Campagne opslaan</button></form></section>'+
   '<section class="pz2-panel"><h3>Mijn campagneplanning</h3><div id="pz2MarketingItems" aria-live="polite">Laden…</div></section></div>';
  var form=$("#pz2Marketing",root),items=$("#pz2MarketingItems",root);
  async function refresh(){
   try{
    var rows=await rpc("pasr_business_marketing_list",{p_business:b.id},true);
    items.innerHTML=rows.length?rows.map(function(x){
     var url=x.card_id?'/zakelijk/flyer/#'+encodeURIComponent(x.card_id):'';
     return '<article class="pz2-planned"><span class="pz2-planned-date">'+escape(x.starts_on)+' – '+escape(x.ends_on)+'</span>'+
      '<strong>'+escape(x.title)+'</strong><small>'+escape(x.card_name||"Algemene actie")+' · '+escape(x.channel)+' · '+escape(x.status)+'</small>'+
      (x.details?'<p>'+escape(x.details)+'</p>':'')+
      (url?'<a class="zk-btn ghost sm" href="'+url+'" target="_blank" rel="noopener">Promotiemateriaal maken</a>':'')+
      '<button type="button" class="zk-btn ghost sm" data-remove="'+escape(x.id)+'">Verwijderen</button></article>';
    }).join(""):'<p>Er zijn nog geen campagnes gepland.</p>';
    items.querySelectorAll("[data-remove]").forEach(function(btn){btn.addEventListener("click",async function(){
     if(!window.confirm("Deze campagne verwijderen?"))return;btn.disabled=true;
     try{await rpc("pasr_business_marketing_delete",{p_event:btn.dataset.remove},true);refresh();}
     catch(e){btn.disabled=false;alert(e.message||"Verwijderen mislukt.");}
    });});
   }catch(e){items.textContent="Kon de planning niet laden: "+(e.message||"onbekend");}
  }
  form.addEventListener("submit",async function(e){
   e.preventDefault();var f=new FormData(form),btn=form.querySelector('button[type="submit"]');
   if(String(f.get("title")||"").trim().length<3||f.get("ends_on")<f.get("starts_on")){
    notice(root,"Controleer de titel en datums.",false);return;
   }
   btn.disabled=true;
   try{
    await rpc("pasr_business_marketing_save",{p_event:{
     business_id:b.id,card_id:f.get("card_id")||null,title:f.get("title"),details:f.get("details"),
     channel:f.get("channel"),status:f.get("status"),starts_on:f.get("starts_on"),ends_on:f.get("ends_on")
    }},true);
    notice(root,"Campagne opgeslagen.",true);form.elements.title.value="";form.elements.details.value="";refresh();
   }catch(e){notice(root,e.message||"Opslaan mislukt.",false);}
   finally{btn.disabled=false;}
  });
  refresh();
 }

 async function locationsView(root,b,rpc){
  root.innerHTML='<div class="zd-ptitle"><div><h2>Vestigingen</h2><p class="zd-sub">Gebruik dezelfde stempelkaart in meerdere filialen. Medewerkers kiezen hun filiaal bij het scannen; statistieken blijven per locatie gescheiden.</p></div></div>'+
   '<div class="pz2-grid"><section class="pz2-panel"><h3>Vestiging toevoegen</h3>'+
   '<form id="pz2Location" class="pz2-form">'+field("Naam vestiging","name","")+
   field("Adres (optioneel)","address","")+'<p class="pz2-notice" role="status"></p>'+
   '<button type="submit" class="zk-btn">Vestiging toevoegen</button></form></section>'+
   '<section class="pz2-panel"><h3>Mijn vestigingen</h3><div id="pz2Locations">Laden…</div></section></div>';
  var form=$("#pz2Location",root),items=$("#pz2Locations",root);
  async function refresh(){
   try {
    var rows=await rpc("pasr_business_locations_list",{p_business:b.id},true);
    var stats=await rpc("pasr_business_location_insights",{p_business:b.id},true).catch(function(){return [];});
    var counts={};(stats||[]).forEach(function(x){counts[x.id]=x.stamps_30d;});
    items.innerHTML=rows.length?rows.map(function(l){
     return '<article class="pz2-planned"><strong>'+escape(l.name)+'</strong>'+
      (l.address?'<small>'+escape(l.address)+'</small>':'')+
      '<small>'+escape(counts[l.id]||0)+' stempels afgelopen 30 dagen · '+(l.active?'Actief':'Inactief')+'</small>'+
      '<button type="button" class="zk-btn ghost sm" data-id="'+escape(l.id)+'" data-active="'+(l.active?'1':'0')+'">'+
      (l.active?'Deactiveren':'Activeren')+'</button></article>';
    }).join(""):'<p>Nog geen vestigingen toegevoegd.</p>';
    items.querySelectorAll("[data-id]").forEach(function(btn){btn.addEventListener("click",async function(){
     var row=rows.find(function(v){return v.id===btn.dataset.id;});
     if(!row)return;btn.disabled=true;
     try{await rpc("pasr_business_location_save",{p_business:b.id,p_name:row.name,p_address:row.address||"",
       p_id:row.id,p_active:!row.active},true);refresh();}
     catch(e){alert(e.message||"Aanpassen mislukt.");btn.disabled=false;}
    });});
   }catch(e){items.textContent="Vestigingen konden niet worden geladen: "+(e.message||"onbekend");}
  }
  form.addEventListener("submit",async function(e){
   e.preventDefault();var f=new FormData(form),btn=form.querySelector('button[type="submit"]');btn.disabled=true;
   try{
    await rpc("pasr_business_location_save",{p_business:b.id,p_name:f.get("name"),p_address:f.get("address")},true);
    notice(root,"Vestiging opgeslagen.",true);form.reset();refresh();
   }catch(e){notice(root,e.message||"Opslaan mislukt.",false);}finally{btn.disabled=false;}
  });
  refresh();
 }

 async function communityView(root,b,rpc){
   // Gezamenlijke acties op uitnodiging (docs/community-invites.md).
   // Eigenaar: uitnodigingen beantwoorden, actie starten, zaken uitnodigen (zoeken, e-mail, link/QR), status per zaak,
   // intrekken, deelnemer verwijderen, instellingen (open voor de eigen plaats, minimum), stoppen, uitstappen.
   // Medewerker: alleen de acties van de eigen zaak en uitgeven (bij het scannen verschijnt de beloning ook vanzelf).
   var owner=!b.role||b.role==="owner";
   var open={};   // id van de actie -> beheerpaneel open
   function err(e,fallback){var m=window.PasrCommunityError&&window.PasrCommunityError(e);return m||(e&&e.message)||fallback||"Dat lukte niet.";}
   function date(v){var d=new Date(v);return isNaN(d)?"":d.toLocaleDateString("nl-NL",{day:"numeric",month:"long",year:"numeric"});}
   var STATE={waiting:["Wacht op deelnemers","wait"],active:["Actief","on"],ended:["Afgelopen",""],cancelled:["Gestopt",""]};
   var STATUS={invited:["Uitgenodigd","wait"],accepted:["Doet mee","on"],declined:["Geweigerd",""],revoked:["Ingetrokken",""]};
   function pill(map,key){var s=map[key]||[key||"",""];return '<span class="zk-pill '+s[1]+'">'+escape(s[0])+'</span>';}
   root.innerHTML='<div class="zd-ptitle"><div><h2>Samenwerkingen</h2><p class="zd-sub">Gezamenlijke beloningen voor bezoeken bij verschillende zaken. Je nodigt zelf de zaken uit waarmee je samenwerkt; een actie start zodra genoeg zaken meedoen. Er worden geen klantgegevens tussen zaken gedeeld. Bij het scannen zie je vanzelf of een klant een gezamenlijke beloning heeft verdiend.</p></div></div>'+
     '<p class="pz2-notice" id="pz2CommunityMsg" role="status" aria-live="polite"></p>'+
     (owner?'<section class="pz2-panel" id="pz2Invites" hidden><h3>Uitnodigingen</h3><p>Andere zaken nodigen je uit voor hun gezamenlijke actie.</p><div id="pz2InviteList"></div></section>'+
       '<section class="pz2-panel" id="pz2Open" hidden><h3>Open acties in je plaats</h3><p>Deze acties staan open voor zaken in jouw plaats. Meedoen kan zonder uitnodiging.</p><div id="pz2OpenList"></div></section>':'')+
     '<div class="pz2-grid">'+(owner?'<section class="pz2-panel"><h3>Nieuwe gezamenlijke actie</h3><form class="pz2-form" id="pz2CommunityCreate">'+
     field("Actienaam","name","")+field("Beloning","reward","")+
     '<div class="pz2-fields">'+field("Verschillende zaken nodig voor de beloning (2–20)","required","3","number")+
     field("Looptijd in dagen (1–366)","days","60","number")+field("Start bij minimaal zoveel deelnemende zaken (2–30)","min","2","number")+'</div>'+
     toggle("Open voor zaken in mijn plaats","open_city",false,"Uit: alleen zaken die jij uitnodigt doen mee. Aan: zaken uit je eigen plaats kunnen ook zelf meedoen.")+
     '<p class="pz2-notice" role="status"></p><button type="submit" class="zk-btn">Samenwerking starten</button></form></section>':'')+
     '<section class="pz2-panel"><h3>'+(owner?"Jouw samenwerkingen":"Acties van je zaak")+'</h3><div id="pz2CommunityList" role="status">Laden…</div></section></div>';
   var form=$("#pz2CommunityCreate",root),list=$("#pz2CommunityList",root),msg=$("#pz2CommunityMsg",root);
   function say(text,ok){msg.textContent=text;msg.dataset.ok=ok?"true":"false";}
   function call(fn,args,done){return rpc(fn,args,true).then(function(r){if(done)say(done,true);return r;},function(e){say(err(e),false);throw e;});}

   async function loadInvites(){
     if(!owner)return;
     var box=$("#pz2Invites",root),out=$("#pz2InviteList",root);
     var rows=[];try{rows=await rpc("pasr_business_community_my_invites",{p_business:b.id},true);}catch(e){rows=[];}
     box.hidden=!(Array.isArray(rows)&&rows.length);
     if(box.hidden)return;
     out.innerHTML=rows.map(function(x){
       var names=Array.isArray(x.participant_names)?x.participant_names:[];
       return '<article class="pz2-planned"><strong>'+escape(x.title)+'</strong>'+
         '<small>Van '+escape([x.initiator_name,x.initiator_city].filter(Boolean).join(", "))+' · '+escape(date(x.starts_at))+' t/m '+escape(date(x.ends_at))+'</small>'+
         '<p>'+escape(x.reward)+(x.required?' na bezoeken bij '+escape(x.required)+' verschillende zaken':'')+'</p>'+
         (names.length?'<small>Doen mee: '+escape(names.join(", "))+'</small>':'')+
         '<div class="pz2-inline"><button class="zk-btn sm" type="button" data-accept="'+escape(x.invite_id)+'">Accepteren</button>'+
         '<button class="zk-btn ghost sm" type="button" data-decline="'+escape(x.invite_id)+'">Weigeren</button></div></article>';
     }).join("");
     out.querySelectorAll("[data-accept],[data-decline]").forEach(function(btn){
       btn.addEventListener("click",async function(){
         var yes=btn.hasAttribute("data-accept"),id=btn.getAttribute(yes?"data-accept":"data-decline");
         if(!yes&&!confirm("Uitnodiging weigeren? De organisator ziet dat je niet meedoet."))return;
         btn.disabled=true;
         try{await call("pasr_business_community_respond",{p_business:b.id,p_invite:id,p_accept:yes},yes?"Je doet nu mee aan deze actie.":"Uitnodiging geweigerd.");refreshAll();}
         catch(e){btn.disabled=false;}
       });
     });
   }

   async function loadOpen(){
     if(!owner)return;
     var box=$("#pz2Open",root),out=$("#pz2OpenList",root);
     var rows=[];try{rows=await rpc("pasr_business_community_open",{p_business:b.id},true);}catch(e){rows=[];}
     box.hidden=!(Array.isArray(rows)&&rows.length);
     if(box.hidden)return;
     out.innerHTML=rows.map(function(x){
       return '<article class="pz2-planned"><strong>'+escape(x.name)+' '+pill(STATE,x.state)+'</strong>'+
         '<small>Van '+escape([x.lead_business,x.lead_city].filter(Boolean).join(", "))+' · '+escape(x.accepted_count)+' van minimaal '+escape(x.min_participants)+' zaken · tot '+escape(date(x.ends_at))+'</small>'+
         '<p>'+escape(x.reward)+'</p><button class="zk-btn ghost sm" type="button" data-join="'+escape(x.id)+'">Meedoen met mijn zaak</button></article>';
     }).join("");
     out.querySelectorAll("[data-join]").forEach(function(btn){
       btn.addEventListener("click",async function(){
         if(!confirm("Met jouw zaak meedoen aan deze actie?"))return;
         btn.disabled=true;
         try{await call("pasr_business_community_join",{p_business:b.id,p_campaign:btn.dataset.join},"Je zaak doet nu mee.");refreshAll();}
         catch(e){btn.disabled=false;}
       });
     });
   }

   // Beheerpaneel van de organisator: uitnodigen, statuslijst, intrekken, verwijderen, instellingen.
   async function manage(box,c){
     box.innerHTML='<div class="pz2-manage">'+
       '<h4>Zaken uitnodigen</h4>'+
       '<form class="pz2-inline" data-search><label class="pz2-field">Zoek op naam of plaats<input name="q" type="search" maxlength="60" autocomplete="off" placeholder="Bijv. bakkerij of Apeldoorn"></label><button class="zk-btn ghost sm" type="submit">Zoeken</button></form>'+
       '<div class="pz2-results" data-results></div>'+
       '<form class="pz2-inline" data-mail><label class="pz2-field">Zaak nog niet in Pasr? Stuur een uitnodiging per e-mail<input name="email" type="email" maxlength="200" autocomplete="off" placeholder="info@zaak.nl (leeg = alleen link en QR-code)"></label><button class="zk-btn ghost sm" type="submit">Uitnodiging maken</button></form>'+
       '<div data-link></div>'+
       '<h4>Status per zaak</h4><div data-status>Laden…</div>'+
       '<h4>Instellingen</h4><form class="pz2-form" data-settings>'+
       toggle("Open voor zaken in mijn plaats","open_city",c.open_same_city,"Zaken uit "+(c.lead_city||"je plaats")+" kunnen zonder uitnodiging meedoen.")+
       '<div class="pz2-inline">'+field("Start bij minimaal zoveel zaken (2–30)","min",String(c.min_participants||2),"number")+'<button class="zk-btn ghost sm" type="submit">Opslaan</button></div></form></div>';
     var results=$("[data-results]",box),linkBox=$("[data-link]",box),status=$("[data-status]",box);
     async function loadStatus(){
       var rows=[];
       try{rows=await rpc("pasr_business_community_invites",{p_business:b.id,p_campaign:c.id},true);}catch(e){status.textContent=err(e);return;}
       status.innerHTML=rows.length?'<ul class="pz2-invitees">'+rows.map(function(x){
         var who=escape(x.name)+(x.city?' <small>'+escape(x.city)+'</small>':'')+(x.organizer?' <small>(organisator)</small>':'');
         var act=x.status==="invited"?'<button class="zk-btn ghost sm" type="button" data-revoke="'+escape(x.invite_id)+'">Intrekken</button>':
           (x.status==="accepted"&&!x.organizer&&x.business_id?'<button class="zk-btn ghost sm danger" type="button" data-remove="'+escape(x.business_id)+'">Verwijderen</button>':'');
         var exp=x.status==="invited"&&x.expires_at?'<small>Link geldig tot '+escape(date(x.expires_at))+'</small>':'';
         return '<li><span class="who">'+who+exp+'</span>'+pill(STATUS,x.status)+act+'</li>';
       }).join("")+'</ul>':'<p>Nog niemand uitgenodigd.</p>';
       status.querySelectorAll("[data-revoke]").forEach(function(btn){btn.addEventListener("click",async function(){
         if(!confirm("Uitnodiging intrekken?"))return;btn.disabled=true;
         try{await call("pasr_business_community_revoke",{p_business:b.id,p_invite:btn.dataset.revoke},"Uitnodiging ingetrokken.");loadStatus();}catch(e){btn.disabled=false;}
       });});
       status.querySelectorAll("[data-remove]").forEach(function(btn){btn.addEventListener("click",async function(){
         if(!confirm("Deze zaak uit de actie halen? Bezoeken bij die zaak tellen dan niet meer mee."))return;btn.disabled=true;
         try{await call("pasr_business_community_remove",{p_business:b.id,p_campaign:c.id,p_target:btn.dataset.remove},"Zaak verwijderd uit de actie.");refreshAll();}catch(e){btn.disabled=false;}
       });});
     }
     $("[data-search]",box).addEventListener("submit",async function(e){
       e.preventDefault();var q=String(new FormData(e.target).get("q")||"").trim();
       results.textContent="Zoeken…";
       var rows=[];try{rows=await rpc("pasr_business_community_search",{p_business:b.id,p_campaign:c.id,p_query:q},true);}catch(x){results.textContent=err(x);return;}
       results.innerHTML=rows.length?'<ul class="pz2-invitees">'+rows.map(function(x){
         var logo=/^data:image\/(png|jpeg);base64,/.test(x.logo_url||"")?'<img src="'+escape(x.logo_url)+'" alt="">':'<span class="mono" aria-hidden="true">'+escape(String(x.name||"?").charAt(0).toUpperCase())+'</span>';
         var can=!x.invite_status||x.invite_status==="declined"||x.invite_status==="revoked";
         return '<li><span class="logo">'+logo+'</span><span class="who">'+escape(x.name)+(x.city?' <small>'+escape(x.city)+'</small>':'')+'</span>'+
           (x.invite_status?pill(STATUS,x.invite_status):'')+(can?'<button class="zk-btn sm" type="button" data-invite="'+escape(x.business_id)+'">Uitnodigen</button>':'')+'</li>';
       }).join("")+'</ul>':'<p>Geen zaken gevonden. Staat de zaak nog niet in Pasr? Stuur dan een uitnodiging per e-mail of deel de link.</p>';
       results.querySelectorAll("[data-invite]").forEach(function(btn){btn.addEventListener("click",async function(){
         btn.disabled=true;
         try{await call("pasr_business_community_invite",{p_business:b.id,p_campaign:c.id,p_target:btn.dataset.invite},"Uitnodiging verstuurd.");btn.replaceWith(document.createRange().createContextualFragment(pill(STATUS,"invited")));loadStatus();}
         catch(x){btn.disabled=false;}
       });});
     });
     $("[data-mail]",box).addEventListener("submit",async function(e){
       e.preventDefault();var email=String(new FormData(e.target).get("email")||"").trim(),btn=e.target.querySelector("button");
       if(email&&!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)){say("Dit e-mailadres klopt niet.",false);return;}
       btn.disabled=true;
       try{
         var r=await call("pasr_business_community_invite_email",{p_business:b.id,p_campaign:c.id,p_email:email||null},email?"Uitnodiging gemaild.":"Uitnodigingslink gemaakt.");
         var qr=window.PasrQrSvg?window.PasrQrSvg(r.link):"";
         linkBox.innerHTML='<div class="zd-invite">'+(qr?'<div class="qr" role="img" aria-label="QR-code van de uitnodiging">'+qr+'</div>':'')+
           '<div><p><b>Uitnodiging klaar.</b> '+(email?"We hebben hem gemaild naar "+escape(email)+". ":"")+'Deel de link of laat de QR-code scannen. Hij werkt 14 dagen, voor één zaak.</p>'+
           '<div class="zk-link">'+escape(r.link)+'</div><p><button class="zk-btn ghost sm" type="button" data-copy>Link kopiëren</button></p></div></div>';
         $("[data-copy]",linkBox).addEventListener("click",function(){
           if(navigator.clipboard)navigator.clipboard.writeText(r.link).then(function(){say("Link gekopieerd.",true);},function(){prompt("Kopieer de link",r.link);});
           else prompt("Kopieer de link",r.link);
         });
         e.target.reset();loadStatus();
       }catch(x){/* melding staat er al */}finally{btn.disabled=false;}
     });
     $("[data-settings]",box).addEventListener("submit",async function(e){
       e.preventDefault();var f=new FormData(e.target),min=Number(f.get("min"));
       if(!Number.isInteger(min)||min<2||min>30){say("Het minimum is 2 tot 30 zaken.",false);return;}
       try{await call("pasr_business_community_settings",{p_business:b.id,p_campaign:c.id,p_open_same_city:f.has("open_city"),p_min_participants:min},"Instellingen opgeslagen.");refreshAll();}catch(x){}
     });
     loadStatus();
   }

   async function refresh(){
     try{
       var rows=await rpc("pasr_business_community_list",{p_business:b.id},true);
       if(!Array.isArray(rows))throw new Error("Ongeldig antwoord");
       list.innerHTML=rows.length?rows.map(function(c){
         var names=Array.isArray(c.participant_names)?c.participant_names:[];
         var lead=[c.lead_business,c.lead_city].filter(Boolean).join(", ");
         var live=c.state==="waiting"||c.state==="active",org=c.role==="owner"||c.is_lead;
         var mine=owner&&org&&live;
         return '<article class="pz2-planned" data-id="'+escape(c.id)+'"><strong>'+escape(c.name)+' '+pill(STATE,c.state)+(org?' <small>organisator</small>':'')+'</strong>'+
           '<small>Initiatief: '+escape(lead)+' · '+escape(c.accepted_count)+' van minimaal '+escape(c.min_participants)+' zaken · '+(c.open_same_city?'open voor '+escape(c.lead_city||"de eigen plaats"):'alleen op uitnodiging')+' · tot '+escape(date(c.ends_at))+'</small>'+
           (names.length?'<small>Doen mee: '+escape(names.join(", "))+'</small>':'')+
           (mine&&c.pending_invites?'<small>'+escape(c.pending_invites)+' uitnodiging'+(c.pending_invites===1?'':'en')+' open</small>':'')+
           '<p>'+escape(c.reward)+' na bezoeken bij '+escape(c.required)+' verschillende zaken</p>'+
           (c.state==="waiting"?'<small>De actie start zodra '+escape(c.min_participants)+' zaken meedoen. Tot dan zien klanten hem niet.</small>':'')+
           (c.state==="active"?'<small>Je zaak neemt deel'+(c.claims_here?' · '+escape(c.claims_here)+'× uitgegeven':'')+'</small>'+
             '<label class="pz2-field">Lidcode bij de kassa<input data-member="'+escape(c.id)+'" placeholder="PZ…" maxlength="40" autocomplete="off"></label>'+
             '<button class="zk-btn sm" type="button" data-claim="'+escape(c.id)+'">Beloning controleren en uitgeven</button>':'')+
           (owner&&live?'<div class="pz2-inline">'+(mine?'<button class="zk-btn ghost sm" type="button" data-manage="'+escape(c.id)+'" aria-expanded="'+(open[c.id]?"true":"false")+'">Uitnodigen en deelnemers</button>'+
               '<button class="zk-btn ghost sm" type="button" data-cancel="'+escape(c.id)+'">Actie stoppen</button>':
             '<button class="zk-btn ghost sm" type="button" data-leave="'+escape(c.id)+'">Uitstappen</button>')+'</div>':'')+
           '<div data-panel="'+escape(c.id)+'"'+(open[c.id]?'':' hidden')+'></div></article>';
       }).join(""):'<p>'+(owner?"Je doet nog niet mee aan een gezamenlijke actie. Start er een, of accepteer een uitnodiging.":"Je zaak doet nog niet mee aan een gezamenlijke actie.")+'</p>';
       function action(attr,fn,question,done){
         list.querySelectorAll("["+attr+"]").forEach(function(btn){
           btn.addEventListener("click",async function(){
             if(!confirm(question))return;
             btn.disabled=true;
             try{await call(fn,{p_business:b.id,p_campaign:btn.getAttribute(attr)},done);refreshAll();}
             catch(e){btn.disabled=false;}
           });
         });
       }
       action("data-leave","pasr_business_community_leave","Uitstappen? Bezoeken bij jouw zaak tellen daarna niet meer mee voor klanten.","Je onderneming doet niet meer mee aan deze actie.");
       action("data-cancel","pasr_business_community_cancel","Actie stoppen? De actie verdwijnt bij klanten en alle deelnemende zaken. Uitgegeven beloningen blijven geregistreerd.","De actie is gestopt.");
       list.querySelectorAll("[data-manage]").forEach(function(btn){
         var id=btn.dataset.manage,box=list.querySelector('[data-panel="'+id+'"]'),c=rows.filter(function(x){return x.id===id;})[0];
         if(open[id])manage(box,c);
         btn.addEventListener("click",function(){
           open[id]=!open[id];box.hidden=!open[id];btn.setAttribute("aria-expanded",open[id]?"true":"false");
           if(open[id])manage(box,c);else box.innerHTML="";
         });
       });
       list.querySelectorAll("[data-claim]").forEach(function(btn){
         btn.addEventListener("click",async function(){
           var id=btn.dataset.claim,entry=list.querySelector('[data-member="'+id+'"]');
           var code=(entry&&entry.value||"").replace(/\s+/g,"").toUpperCase();
           if(!/^PZ[A-Z0-9]{5,38}$/.test(code)){say("Vul een geldige PZ-lidcode in.",false);return;}
           if(!confirm("De server controleert de bezoeken. Beloning nu eenmalig uitgeven?"))return;
           btn.disabled=true;
           try{
             var result=await rpc("pasr_business_community_claim",
               {p_campaign:id,p_business:b.id,p_member_code:code},true);
             say("Beloning uitgegeven: "+(result.reward||"gezamenlijke beloning"),true);refresh();
           }catch(e){say(err(e,"Deze beloning kan niet worden uitgegeven."),false);btn.disabled=false;}
         });
       });
     }catch(e){list.textContent="Samenwerkingen konden niet worden geladen: "+err(e,"onbekend");}
   }
   function refreshAll(){loadInvites();loadOpen();refresh();}
   if(form)form.addEventListener("submit",async function(e){
     e.preventDefault();var f=new FormData(form),name=String(f.get("name")||"").trim(),
       reward=String(f.get("reward")||"").trim(),required=Number(f.get("required")),days=Number(f.get("days")),min=Number(f.get("min"));
     if(name.length<3||name.length>80||reward.length<3||reward.length>120||
        !Number.isInteger(required)||required<2||required>20||
        !Number.isInteger(days)||days<1||days>366||!Number.isInteger(min)||min<2||min>30){
       notice(form,"Controleer naam, beloning, aantal zaken, minimum en looptijd.",false);return;
     }
     var btn=form.querySelector("button[type=submit]");btn.disabled=true;
     try{
       var r=await rpc("pasr_business_community_create",{p_business:b.id,p_name:name,p_reward:reward,p_required:required,p_days:days,
         p_open_same_city:f.has("open_city"),p_min_participants:min},true);
       form.reset();notice(form,"Samenwerking aangemaakt. Nodig nu de zaken uit waarmee je samenwerkt.",true);
       if(r&&r.id)open[r.id]=true;
       refresh();
     }catch(e){notice(form,err(e,"Opslaan mislukt."),false);}finally{btn.disabled=false;}
   });
   refreshAll();
 }
 window.PasrLoyalty2={settings:settingsView,coupons:couponDashboard,insights:insightsView,marketing:marketingView,locations:locationsView,community:communityView,publicPage:publicPage};
})();
