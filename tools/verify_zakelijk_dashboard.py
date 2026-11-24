#!/usr/bin/env python3
"""PR-check: dashboard navigation, feature modules and generated website agree."""
from pathlib import Path
import re

root=Path(__file__).resolve().parent.parent
html=(root/"website/zakelijk/dashboard/index.html").read_text()
generator=(root/"tools/make_zakelijk.py").read_text()
script=(root/"website/assets/zakelijk.js").read_text()
module=(root/"website/assets/loyalty2.js").read_text()
css=(root/"website/assets/zakelijk.css").read_text()

def require(ok,msg):
    if not ok: raise SystemExit("FAILED: "+msg)
    print("PASS:",msg)

for source,name in [(html,"Published dashboard HTML"),(generator,"Dashboard page generator")]:
    require(source.find('/assets/loyalty2.js')>=0,f"{name} includes new loyalty code")
    require(source.find('/assets/loyalty2.js')<source.find('/assets/zakelijk.js'),
            f"{name} loads feature module before dashboard renderer")
require('grid-template-columns: repeat(5,minmax(0,1fr))' in css,
        "Dashboard tabs use a responsive grid, not a single compressed row")
for breakpoint in ("980px","760px","470px"):
    require(breakpoint in css,"Dashboard has responsive breakpoint "+breakpoint)
tabs=re.findall(r'\{ id: "([a-z-]+)", label: ',script)
require(len(tabs)>=12 and len(tabs)==len(set(tabs)), "Dashboard contains 12+ unique tabs")
require('/assets/promo-codes-business.js' in html and '/assets/promo-codes-business.js' in generator, "Custom promo-code business module included")
require('window.PasrPromoCodes.mount(panel, b, rpc)' in script, "Promo codes use own RPC-backed dashboard view")
for tab in tabs:
    require(re.search(r'VIEWS(?:\.'+re.escape(tab)+r'|\["'+re.escape(tab)+r'"\])\s*=',script) is not None,
            f"Tab {tab} has a view controller")
mapping={
 "acties":"settings","vestigingen":"locations","marketing":"marketing",
 "inzichten":"insights","kortingsbonnen":"coupons","samenwerkingen":"community"
}
for tab,fn in mapping.items():
    require(f"window.PasrLoyalty2.{fn}(panel, b, rpc)" in script,tab+" routes to its module")
    require(re.search(r'\b'+fn+r':\w+',module) is not None,fn+" exported from module")
for rpc in ("pasr_business_program","pasr_business_coupon_check",
            "pasr_business_marketing_list","pasr_business_locations_list",
            "pasr_business_loyalty_insights","pasr_business_community_list",
            "pasr_business_community_create","pasr_business_community_claim"):
    require(rpc in module,"Feature calls "+rpc)
for field in ('campaign_start','campaign_end','vip_silver_benefit','vip_gold_benefit'):
    require(field in module,"Web preserves native app setting "+field)
print("PASR ZAKELIJK DASHBOARD INTEGRITY VERIFIED")
