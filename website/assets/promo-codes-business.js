(function(){
"use strict";
function esc(v){return String(v==null?"":v).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];});}
function mount(root,b,rpc){
root.innerHTML='<div class="zd-ptitle"><div><h2>Eigen actiecodes</h2><p class="zd-sub">Maak herbruikbare kortingscodes die klanten aan de kassa noemen, gescheiden van persoonlijke kortingsbonnen.</p></div></div>'+
'<div class="pz2-grid"><section class="pz2-panel"><h3 id="pzPromoFormHeading">Nieuwe actiecode</h3><form id="pzPromoForm" class="pz2-form">'+
'<label class="pz2-field">Code (4–24 tekens)<input name="code" maxlength="24" pattern="[A-Za-z0-9][A-Za-z0-9-]{3,23}" placeholder="HERFST20" autocomplete="off" required></label>'+
'<label class="pz2-field">Naam actie<input name="title" maxlength="80" minlength="3" required></label>'+
'<label class="pz2-field">Korting<select name="discount_type"><option value="percent">Percentage (%)</option><option value="amount">Vast bedrag (€)</option></select></label>'+
'<label class="pz2-field">Korting<input name="discount_value" type="number" min="0.01" step="0.01" value="10" required></label>'+
'<label class="pz2-field">Minimale besteding<input name="min_spend" type="number" min="0" step="0.01" value="0"></label>'+
'<label class="pz2-field">Startdatum<input name="starts_at" type="date" required></label>'+
'<label class="pz2-field">Einddatum<input name="ends_at" type="date" required></label>'+
'<label class="pz2-field">Maximaal gebruik<input name="max_uses" type="number" min="1" max="100000" value="100" required></label>'+
'<label class="pz2-toggle"><span>Actiecode activeren</span><input name="active" type="checkbox"></label>'+
'<p id="pzPromoNotice" class="pz2-notice" role="status"></p><button class="zk-btn" type="submit">Actiecode opslaan</button> <button class="zk-btn ghost" id="pzPromoReset" type="button">Nieuw</button></form></section>'+
'<section class="pz2-panel"><h3>Mijn actiecodes</h3><div id="pzPromoList">Laden…</div>'+
'<h3>Controleren en verzilveren</h3><p>Scan uitsluitend de persoonlijke PA-code uit de Pasr: Klantenkaarten-app. De algemene ondernemerscode is niet verzilverbaar.</p><label class="pz2-field">Persoonlijke PA-code<input id="pzPromoCode" autocomplete="off"></label>'+
'<p id="pzPromoResult" role="status"></p><button class="zk-btn ghost" id="pzPromoCheck" type="button">Controleren</button> '+
'<button class="zk-btn" id="pzPromoRedeem" type="button" disabled>Gebruik registreren</button>'+
'<p class="zd-sub">Registreer pas nadat de korting is toegepast. Iedere registratie telt één keer.</p></section></div>';
var form=root.querySelector("#pzPromoForm"),list=root.querySelector("#pzPromoList"),
 notice=root.querySelector("#pzPromoNotice"),result=root.querySelector("#pzPromoResult"),
 check=root.querySelector("#pzPromoCheck"),redeem=root.querySelector("#pzPromoRedeem"),code=root.querySelector("#pzPromoCode");
var today=new Date(),later=new Date(Date.now()+30*86400000),editingID=null,allCodes=[];
form.elements.starts_at.value=today.toISOString().slice(0,10);
form.elements.ends_at.value=later.toISOString().slice(0,10);
function money(v,type){return type==="percent"?v+"%":new Intl.NumberFormat("nl-NL",{style:"currency",currency:"EUR"}).format(v);}
async function refresh(){try{
var rows=await rpc("pasr_business_promo_list",{p_business:b.id},true);
allCodes=(rows||[]).filter(function(row){return !row.deleted;});
var card=(b.cards||[]).find(function(c){return !!c.logo;})||{};
var logo=card.logo&&/^[A-Za-z0-9+/=]+$/.test(card.logo)?
 '<img alt="Bedrijfslogo" src="data:image/'+(card.logo.indexOf("/9j/")===0?"jpeg":"png")+';base64,'+card.logo+'" style="width:44px;height:44px;object-fit:contain;background:white;border-radius:9px">':
 '<span aria-hidden="true">🏬</span>';
list.innerHTML=allCodes.length?allCodes.map(function(x,i){
 var shade=x.deleted||!x.active?"#777480":/^#[0-9a-f]{6}$/i.test(card.color||"")?card.color:"#6A5CFF";
 return '<article class="zk-panel"><div style="background:'+shade+';color:white;padding:18px;border-radius:20px">'+
 '<div style="display:flex;align-items:center;justify-content:space-between">'+logo+'<b>pasr.</b></div>'+
 '<h3>'+esc(money(x.discount_value,x.discount_type))+' KORTING</h3>'+
 '<b>'+esc(x.title)+'</b><p>Actiecode · '+esc(x.deleted?"Verwijderd":x.active?"Actief":"Gepauzeerd")+
 ' · '+esc(x.used_count)+'/'+esc(x.max_uses)+' gebruikt</p></div>'+
 '<p class="zd-sub">Beheercode: '+esc(x.code)+' (alleen zichtbaar voor ondernemer)</p>'+
 (!x.deleted?'<button type="button" class="zk-btn ghost" data-editpromo="'+i+'">Bewerken</button> '+
 '<button type="button" class="zk-btn ghost" data-removepromo="'+i+'">Verwijderen</button>':'')+'</article>';
}).join(""):'<p>Geen actiecodes.</p>';
list.querySelectorAll("[data-editpromo]").forEach(function(btn){btn.addEventListener("click",function(){
 var x=allCodes[Number(btn.dataset.editpromo)];editingID=x.id;
 ["code","title","discount_type","discount_value","min_spend","max_uses"].forEach(function(k){form.elements[k].value=x[k];});
 form.elements.starts_at.value=String(x.starts_at).slice(0,10);
 form.elements.ends_at.value=String(x.ends_at).slice(0,10);
 form.elements.active.checked=!!x.active;
 root.querySelector("#pzPromoFormHeading").textContent="Actiecode bewerken · "+x.title;
 form.scrollIntoView({behavior:"smooth",block:"start"});
});});
list.querySelectorAll("[data-removepromo]").forEach(function(btn){btn.addEventListener("click",async function(){
 var x=allCodes[Number(btn.dataset.removepromo)];
 if(!window.confirm("Actiecode "+x.title+" verwijderen? Persoonlijke PA-bewijzen worden onbruikbaar, maar historie blijft bewaard."))return;
 btn.disabled=true;
 try{await rpc("pasr_business_discount_remove",{p_business:b.id,p_id:x.id,p_kind:"code"},true);
    notice.textContent="Actiecode verwijderd, historie behouden.";if(editingID===x.id)editingID=null;await refresh();
 }catch(e){notice.textContent=e.message||"Verwijderen mislukt.";btn.disabled=false;}
});});
}catch(e){list.textContent="Laden mislukt: "+(e.message||"onbekend");}}
form.addEventListener("submit",async function(ev){
 ev.preventDefault();var f=new FormData(form),name=String(f.get("code")||"").trim().toUpperCase(),value=Number(f.get("discount_value")),min=Number(f.get("min_spend")||0);
 if(!/^[A-Z0-9][A-Z0-9-]{3,23}$/.test(name)||value<=0||min<0||(f.get("discount_type")==="percent"&&value>100)||f.get("ends_at")<=f.get("starts_at")){notice.textContent="Controleer code, korting en datums.";return;}
 var btn=form.querySelector('button[type="submit"]');btn.disabled=true;
 try{var payload={business_id:b.id,code:name,title:f.get("title"),discount_type:f.get("discount_type"),discount_value:value,min_spend:min,starts_at:f.get("starts_at")+"T00:00:00Z",ends_at:f.get("ends_at")+"T23:59:59Z",max_uses:Number(f.get("max_uses")),active:f.has("active")};
 if(editingID)payload.id=editingID;
 await rpc("pasr_business_promo_save",{p_promo:payload},true);
 notice.textContent="Actiecode opgeslagen.";editingID=null;form.reset();
 root.querySelector("#pzPromoFormHeading").textContent="Nieuwe actiecode";await refresh();
 }catch(e){notice.textContent=e.message||"Opslaan mislukt.";}finally{btn.disabled=false;}
});
root.querySelector("#pzPromoReset").addEventListener("click",function(){
 editingID=null;form.reset();root.querySelector("#pzPromoFormHeading").textContent="Nieuwe actiecode";
});
code.addEventListener("input",function(){redeem.disabled=true;result.textContent="";});
check.addEventListener("click",async function(){redeem.disabled=true;try{
var x=await rpc("pasr_business_promo_check",{p_code:code.value.trim().toUpperCase()},true);
redeem.disabled=!x.valid;result.textContent=x.valid?"Geldig: "+x.title+" · "+money(x.discount_value,x.discount_type)+" · "+x.remaining+" over":"Actiecode niet geldig, verlopen of opgebruikt.";
}catch(e){result.textContent=e.message||"Controleren mislukt.";}});
redeem.addEventListener("click",async function(){redeem.disabled=true;try{
var x=await rpc("pasr_business_promo_redeem",{p_code:code.value.trim().toUpperCase()},true);
result.textContent="Gebruik geregistreerd · "+x.remaining+" over";await refresh();
}catch(e){result.textContent=e.message||"Registreren mislukt.";}});
refresh();
}
window.PasrPromoCodes={mount:mount};
})();