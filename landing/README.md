# What Happened Last Night? — landing + QR flyer

Everything for the site and the printed flyer lives in this folder.

## Files

| File | Purpose |
|---|---|
| `index.html` | The landing page. Plays `Final.mp4`, shows `appPhoto.jpg`, displays the `CLU.T6.PETA` location and the vote CTA. |
| `Final.mp4` | The 20-second entry video (served inline on the page). |
| `appPhoto.jpg` | App screenshot (web-optimized, 330 KB). |
| `flyer.png` | Print-ready A5 poster @ 300 DPI with the QR code. Send this to Xerox. |
| `make_flyer.py` | Regenerates `flyer.png` if anything changes (URL, location code, tagline…). |

## Update the site

Drag the **`landing/`** folder onto https://app.netlify.com/drop (or your existing Netlify site) and it replaces the live version. URL stays `https://what-happend-last-night.netlify.app/`.

## Regenerate the flyer

```bash
pip install qrcode pillow      # one-time
python3 make_flyer.py "https://what-happend-last-night.netlify.app/" --out flyer.png
```

Optional flags:
```bash
--team "What Happened Last Night?"
--tagline "Watch our entry — then vote for us."
--location "CLU.T6.PETA"
--width 1748 --height 2480     # A5 portrait @ 300 DPI (default)
```
