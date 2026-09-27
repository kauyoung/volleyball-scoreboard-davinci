"""
Volleyball match YouTube thumbnail (design approved 2026-09-25).

1280x720 JPG: darkened match frame, MATCH REPLAY tag + date, team logo top
right, HOME TEAM (green) vs OPPONENT (white), one score tile per set along
the bottom. No result banner, no accent line.

Usage:
  python make-thumbnail.py <match.json> <frame.jpg> <out.jpg> [fonts_dir]

<frame.jpg> is any frame grabbed from the finished video (the bottom 20% is
cropped off, so the burned-in scoreboard doesn't show). fonts_dir must contain
"Gotham Narrow Bold.otf" and "Gotham Medium.otf" (default: C:/Windows/Fonts).
"""
import json, sys, os, datetime
from PIL import Image, ImageDraw, ImageFont, ImageEnhance

LOGO = "C:/Users/YOURNAME/scoreboard-pipeline/team-logo.jpg"
W, H = 1280, 720
GREEN = (112, 213, 73); WHITE = (255, 255, 255); INK = (2, 3, 3)


def set_scores(events):
    """Final score of each set, from the last event of each set."""
    last = {}
    for e in events:
        last[e["set"]] = (e["score1"], e["score2"])
    return [last[s] for s in sorted(last)]


def main(match_path, frame_path, out_path, fonts=r"C:\Windows\Fonts"):
    m = json.load(open(match_path, encoding="utf-8"))
    team1 = (m.get("team1") or "Home Team").upper()
    team2 = (m.get("team2") or "Opponent").upper()
    try:
        date = datetime.date.fromisoformat(m["date"]).strftime("%b %d, %Y").upper()
    except Exception:
        date = ""
    NB = os.path.join(fonts, "Gotham Narrow Bold.otf")
    MED = os.path.join(fonts, "Gotham Medium.otf")
    f = lambda p, s: ImageFont.truetype(p, s)

    bg = Image.open(frame_path).convert("RGB")
    bw, bh = bg.size
    ch = int(bh * 0.80); cw = int(ch * 16 / 9); x0 = max(0, (bw - cw) // 2)
    bg = bg.crop((x0, 0, x0 + cw, ch)).resize((W, H), Image.LANCZOS)
    bg = ImageEnhance.Brightness(bg).enhance(0.55)
    grad = Image.new("L", (W, H)); gd = ImageDraw.Draw(grad)
    for x in range(W):
        gd.line([(x, 0), (x, H)], fill=int(235 * max(0, 1 - x / (W * 0.85))))
    bg = Image.composite(Image.new("RGB", (W, H), INK), bg, grad)
    band = Image.new("L", (W, H)); bd = ImageDraw.Draw(band)
    for y in range(H - 200, H):
        bd.line([(0, y), (W, y)], fill=int(200 * (y - (H - 200)) / 200))
    bg = Image.composite(Image.new("RGB", (W, H), INK), bg, band)
    d = ImageDraw.Draw(bg)
    L = 70

    d.rounded_rectangle([L, 62, L + 250, 108], radius=23, fill=GREEN)
    d.text((L + 125, 86), "MATCH REPLAY", font=f(NB, 26), fill=INK, anchor="mm")
    d.text((L + 270, 86), date, font=f(MED, 26), fill=(220, 220, 220), anchor="lm")

    # Shrink the opponent's name if it's long, so it never runs off the frame.
    maxw = W - L - 60
    s2 = 88
    while s2 > 48 and d.textlength(team2, font=f(NB, s2)) > maxw:
        s2 -= 4
    d.text((L, 175), team1, font=f(NB, 128), fill=GREEN)
    d.text((L, 318), "vs", font=f(MED, 48), fill=(200, 200, 200))
    d.text((L, 375), team2, font=f(NB, s2), fill=WHITE)

    x, y, hgt = L, 575, 92
    for i, (a, b) in enumerate(set_scores(m["events"]), start=1):
        label, score = f"SET {i}", f"{a}\u2013{b}"
        lf, sf = f(MED, 26), f(NB, 58)
        lw = d.textlength(label, font=lf); sw = d.textlength(score, font=sf)
        w = int(28 + lw + 22 + sw + 30)
        d.rounded_rectangle([x, y, x + w, y + hgt], radius=18, fill=(28, 30, 30),
                            outline=(70, 72, 72), width=2)
        d.text((x + 28, y + hgt / 2), label, font=lf, fill=(170, 170, 170), anchor="lm")
        d.text((x + 28 + lw + 22, y + hgt / 2 + 2), score, font=sf, fill=WHITE, anchor="lm")
        x += w + 22

    if os.path.exists(LOGO):
        logo = Image.open(LOGO).convert("RGB").resize((190, 190), Image.LANCZOS)
        mask = Image.new("L", (190, 190)); ImageDraw.Draw(mask).ellipse([0, 0, 189, 189], fill=255)
        cx, cy = W - 165, 165
        d.ellipse([cx - 101, cy - 101, cx + 101, cy + 101], fill=GREEN)
        bg.paste(logo, (cx - 95, cy - 95), mask)

    bg.save(out_path, quality=92)
    print("saved", out_path)


if __name__ == "__main__":
    main(*sys.argv[1:])
