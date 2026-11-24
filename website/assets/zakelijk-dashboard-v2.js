/* Progressive Pasr Zakelijk dashboard layer. No APIs, business permissions or stored records are replaced. */
(function(){
 "use strict";
 if(document.body.dataset.page!=="zk-dashboard")return;
 var app=document.getElementById("zk-app");if(!app)return;
 var scheduled=false;
 function node(tag,cls,text){var el=document.createElement(tag);if(cls)el.className=cls;if(text!=null)el.textContent=text;return el;}
 function install(){
  scheduled=false;
  var tabs=app.querySelector(".zd-tabs"),panel=app.querySelector("#zd-panel");
  if(tabs&&!app.querySelector(".zd-mobile-toggle")){
   var toggle=node("button","zd-mobile-toggle","☰  Menu zakelijke omgeving");toggle.type="button";toggle.setAttribute("aria-expanded","false");
   toggle.addEventListener("click",function(){var open=tabs.classList.toggle("zd-tabs-open");toggle.setAttribute("aria-expanded",String(open));toggle.textContent=(open?"✕  Menu sluiten":"☰  Menu zakelijke omgeving");});
   tabs.before(toggle);
  }
  if(tabs){tabs.querySelectorAll("[data-tab]").forEach(function(btn){if(!btn.dataset.zdEnhanced){btn.dataset.zdEnhanced="1";btn.addEventListener("click",function(){tabs.classList.remove("zd-tabs-open");var t=app.querySelector(".zd-mobile-toggle");if(t){t.setAttribute("aria-expanded","false");t.textContent="☰  Menu zakelijke omgeving";}});}});}
  if(panel&&app.querySelector("#tab-overzicht[aria-selected=true]")&&!panel.querySelector(".zd-quick-actions")){
   var quick=node("div","zd-quick-actions");
   [["＋ Nieuwe stempelkaart","kaarten"],["% Kortingsbon maken","kortingsbonnen"],["◎ Scannen","scannen"],["↗ Promotiemateriaal","kaarten"]].forEach(function(item){
    var btn=node("button","",item[0]);btn.type="button";btn.addEventListener("click",function(){var dest=app.querySelector('[data-tab="'+item[1]+'"]');if(dest)dest.click();});quick.appendChild(btn);
   });
   var title=panel.querySelector(".zd-ptitle");if(title)title.after(quick);else panel.prepend(quick);
  }
  var form=panel&&panel.querySelector("#pz2Coupon");if(!form||form.dataset.zdPreview)return;
  form.dataset.zdPreview="1";
  var previewPanel=node("section","pz2-panel zd-preview-panel");var h=node("h3","","Live voorbeeld in je huisstijl"),sub=node("p","zd-preview-sub","Voorbeeld van de uitstraling. Een unieke QR-code ontstaat pas wanneer een klant de bon bewaart.");
  var card=node("div","zd-coupon-preview");var top=node("div","zd-coupon-top"),business=node("div","zd-coupon-business"),value=node("div","zd-coupon-value"),desc=node("div","zd-coupon-desc"),bottom=node("div","zd-coupon-bottom"),terms=node("span"),brand=node("strong","","pasr.");
  top.append(business,value,desc);bottom.append(terms,brand);card.append(top,bottom);
  var note=node("p","zd-coupon-note","Kleur en logo volgen je bestaande zakelijke kaart. Voor deze preview worden geen fictieve QR- of barcodes uitgegeven.");
  previewPanel.append(h,sub,card,note);
  form.after(previewPanel);
  var heading=app.querySelector(".zd-biz h1"),logo=app.querySelector(".zd-logo"),logoImg=logo&&logo.querySelector("img");
  if(logoImg&&logoImg.getAttribute("src")){var img=document.createElement("img");img.src=logoImg.src;img.alt="";business.append(img);}
  business.append(node("span","",heading?heading.textContent:"Jouw zaak"));
  var color=logo&&getComputedStyle(logo).backgroundColor;if(color)card.style.setProperty("--coupon-color",color);
  function update(){
   var f=new FormData(form),amount=Number(f.get("discount_value")||0),kind=f.get("discount_type");
   value.textContent=kind==="percent"?amount.toLocaleString("nl-NL")+"% KORTING":new Intl.NumberFormat("nl-NL",{style:"currency",currency:"EUR"}).format(amount)+" KORTING";
   desc.textContent=String(f.get("title")||"Nieuwe kortingsbon");
   var min=Number(f.get("min_spend")||0),end=f.get("ends_at");
   terms.textContent=(min>0?"Vanaf € "+min.toLocaleString("nl-NL",{minimumFractionDigits:2})+" · ":"")+(end?"Geldig t/m "+new Date(end+"T12:00:00").toLocaleDateString("nl-NL"):"");
  }
  form.addEventListener("input",update);form.addEventListener("change",update);update();
 }
 var observer=new MutationObserver(function(){if(!scheduled){scheduled=true;requestAnimationFrame(install);}});
 observer.observe(app,{childList:true,subtree:true});install();
})();
