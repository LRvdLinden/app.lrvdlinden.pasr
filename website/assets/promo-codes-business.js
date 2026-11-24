(function(){
"use strict";
function esc(v){return String(v==null?"":v).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];});}
function mount(root,b,rpc){
root.innerHTML='<div class="zd-ptitle"><div><h2>Eigen actiecodes</h2><p class="zd-sub">Maak herbruikbare kortingscodes die klanten aan de kassa noemen, gescheiden van persoonlijke kortingsbonnen.</p></div></div>'+
'<div class="pz2-grid"><section class="pz2-panel"><h3>Nieuwe actiecode</h3><form id="pzPromoForm" class="pz2-form">'+
'<label class="pz2-field">Code (4–24 tekens)<input name="code" maxlength="24" pattern="[A-Za-z0-9][A-Za-z0-9-]{3,23}" placeholder="HERFST20" autocomplete="off" required></label>'+
'<label class="pz2-field">Naam actie<input name="title" maxlength="80" minlength="3" required></label>'+
'<label class="pz2-field">Korting<select name="discount_type"><option value="percent">Percentage (%)</option><option value="amount">Vast bedrag (€)</option></select></label>'+
'<label class="pz2-field">Korting<input name="discount_value" type="number" min="0.01" step="0.01" value="10" required></label>'+
'<label class="pz2-field">Minimale besteding<input name="min_spend" type="number" min="0" step="0.01" value="0"></label>'+
'<label class="pz2-field">Startdatum<input name="starts_at" type="date" required></label>'+
'<label class="pz2-field">Einddatum<input name="ends_at" type="date" required></label>'+
'<label class="pz2-field">Maximaal gebruik<input name="max_uses" type="number" min="1" max="100000" value="100" required></label>'+
'<label class="pz2-toggle"><span>Actiecode activeren</span><input name="active" type="checkbox"></label>'+
'<p id="pzPromoNotice" class="pz2-notice" role="status"></p><button class="zk-btn" type="submit">Actiecode opslaan</button></form></section>'+
'<section class="pz2-panel"><h3>Mijn actiecodes</h3><div id="pzPromoList">Laden…</div>'+
'<h3>Controleren en verzilveren</h3><label class="pz2-field">Actiecode<input id="pzPromoCode" autocomplete="off"></label>'+
'<p id="pzPromoResult" role="status"></p><button class="zk-btn ghost" id="pzPromoCheck" type="button">Controleren</button> '+
'<button class="zk-btn" id="pzPromoRedeem" type="button" disabled>Gebruik registreren</button>'+
'<p class="zd-sub">Registreer pas nadat de korting is toegepast. Iedere registratie telt één keer.</p></section></div>';
var form=root.querySelector("#pzPromoForm"),list=root.querySelector("#pzPromoList"),
 notice=root.querySelector("#pzPromoNotice"),result=root.querySelector("#pzPromoResult"),
 check=root.querySelector("#pzPromoCheck"),redeem=root.querySelector("#pzPromoRedeem"),code=root.querySelector("#pzPromoCode");
var today=new Date(),later=new Date(Date.now()+30*86400000);
form.elements.starts_at.value=today.toISOString().slice(0,10);
form.elements.ends_at.value=later.toISOString().slice(0,10);
function money(v,type){return type==="percent"?v+"%":new Intl.NumberFormat("nl-NL",{style:"currency",currency:"EUR"}).format(v);}
async function refresh(){try{
var rows=await rpc("pasr_business_promo_list",{p_business:b.id},true);
list.innerHTML=(rows||[]).length?rows.map(function(x){return '<div class="zk-panel"><b>'+esc(x.code)+'</b> · '+esc(x.title)+'<p class="zd-sub">'+esc(money(x.discount_value,x.discount_type))+' · '+esc(x.used_count)+'/'+esc(x.max_uses)+' gebruikt · '+(x.active?'Actief':'Uit')+'</p></div>';}).join(""):'<p>Geen actiecodes.</p>';
}catch(e){list.textContent="Laden mislukt: "+(e.message||"onbekend");}}
form.addEventListener("submit",async function(ev){
 ev.preventDefault();var f=new FormData(form),name=String(f.get("code")||"").trim().toUpperCase(),value=Number(f.get("discount_value")),min=Number(f.get("min_spend")||0);
 if(!/^[A-Z0-9][A-Z0-9-]{3,23}$/.test(name)||value<=0||min<0||(f.get("discount_type")==="percent"&&value>100)||f.get("ends_at")<=f.get("starts_at")){notice.textContent="Controleer code, korting en datums.";return;}
 var btn=form.querySelector('button[type="submit"]');btn.disabled=true;
 try{await rpc("pasr_business_promo_save",{p_promo:{business_id:b.id,code:name,title:f.get("title"),discount_type:f.get("discount_type"),discount_value:value,min_spend:min,starts_at:f.get("starts_at")+"T00:00:00Z",ends_at:f.get("ends_at")+"T23:59:59Z",max_uses:Number(f.get("max_uses")),active:f.has("active")}},true);
 notice.textContent="Actiecode opgeslagen.";form.elements.code.value="";form.elements.title.value="";await refresh();
 }catch(e){notice.textContent=e.message||"Opslaan mislukt.";}finally{btn.disabled=false;}
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