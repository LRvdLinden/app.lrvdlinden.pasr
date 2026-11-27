"""Rendert de reels frame voor frame met Playwright en ffmpeg.

  python3 render.py <buildmap> <uitmap> preview <reel> t1 t2 ...     -> PNG's van losse momenten
  python3 render.py <buildmap> <uitmap> video <reel> <cut1,cut2,...>  -> één mp4 per scène, concat, stille audio

De build-map wordt geserveerd op http://localhost:8766 (site-CSS op :8765). Frames: JPEG q92, 1080x1920, 30 fps.
De scènegrenzen liggen in rustige stukken, zodat elke overgang (crossfade/beweging) binnen één scènebestand valt.
"""
import json, os, subprocess, sys, shutil
from playwright.sync_api import sync_playwright

B, OUT, MODE, REEL = sys.argv[1:5]
ARGS = sys.argv[5:]
FPS = 30
os.makedirs(OUT, exist_ok=True)
T = json.load(open(B + "/reels.json"))[REEL]


def open_page(p):
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": 1080, "height": 1920}, device_scale_factor=1)
    pg.goto(f"http://localhost:8766/reel-{REEL}.html", wait_until="networkidle")
    pg.wait_for_function("window.__ready===true")
    pg.wait_for_timeout(300)
    return b, pg


def enc(frames_dir, n0, n, dst):
    tmp = dst[:-4] + ".tmp.mp4"
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-start_number", str(n0),
           "-i", f"{frames_dir}/f%05d.jpg", "-frames:v", str(n), "-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
           "-pix_fmt", "yuv420p", "-r", str(FPS), "-movflags", "+faststart", tmp]
    subprocess.run(cmd, check=True)
    os.replace(tmp, dst)


with sync_playwright() as p:
    b, pg = open_page(p)
    if MODE == "preview":
        for t in ARGS:
            pg.evaluate(f"setT({float(t)})")
            pg.screenshot(path=f"{OUT}/{REEL}-{float(t):05.2f}.png")
            print("preview", t)
    else:
        total = round(T * FPS)
        cuts = [0] + [round(float(c) * FPS) for c in ARGS[0].split(",")] + [total]
        fdir = f"{OUT}/frames-{REEL}"
        shutil.rmtree(fdir, ignore_errors=True); os.makedirs(fdir)
        segs = []
        for si in range(len(cuts) - 1):
            a, z = cuts[si], cuts[si + 1]
            for f in range(a, z):
                pg.evaluate(f"setT({f / FPS})")
                pg.screenshot(path=f"{fdir}/f{f:05d}.jpg", type="jpeg", quality=92)
            seg = f"{OUT}/{REEL}-scene{si + 1}.mp4"
            enc(fdir, a, z - a, seg)
            segs.append(seg)
            for f in range(a, z):
                os.remove(f"{fdir}/f{f:05d}.jpg")
            print("scene", si + 1, a, z, flush=True)
        lst = f"{OUT}/{REEL}-concat.txt"
        open(lst, "w").write("".join(f"file '{os.path.abspath(s)}'\n" for s in segs))
        joined = f"{OUT}/{REEL}-video.mp4"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined], check=True)
        final = f"{OUT}/{REEL}-reel.mp4"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", joined, "-f", "lavfi", "-i",
                        "anullsrc=channel_layout=stereo:sample_rate=48000", "-map", "0:v", "-map", "1:a",
                        "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart",
                        final[:-4] + ".tmp.mp4"], check=True)
        os.replace(final[:-4] + ".tmp.mp4", final)
        print("klaar", final)
    b.close()
