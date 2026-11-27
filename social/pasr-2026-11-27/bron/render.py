import sys, os, glob
from playwright.sync_api import sync_playwright
B=sys.argv[1]; out=sys.argv[2]; only=sys.argv[3] if len(sys.argv)>3 else ''
os.makedirs(out, exist_ok=True)
with sync_playwright() as p:
    b=p.chromium.launch()
    for f in sorted(glob.glob(B+'/*.html')):
        n=os.path.basename(f)[:-5]
        if n=='hero_panel' or (only and only not in n): continue
        w,h=map(int, n.rsplit('-',1)[1].split('x'))
        pg=b.new_page(viewport={'width':w,'height':h}, device_scale_factor=1, reduced_motion='reduce')
        pg.goto('http://localhost:8766/'+os.path.basename(f), wait_until='networkidle')
        pg.wait_for_function('window.__fit===true'); pg.wait_for_timeout(300)
        pg.screenshot(path=f'{out}/{n}.png'); pg.close(); print(n)
    b.close()
