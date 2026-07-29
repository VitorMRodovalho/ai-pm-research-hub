"""Mede a geometria real dos elementos de uma peca (Chrome --dump-dom + getBoundingClientRect).

Serve para provar por numero, e nao por olho, que nao ha colisao entre:
  - a esfera ciano decorativa (.dot) e qualquer texto,
  - o pill da data (.quando) e o rodape (.rodape).

Uso: from qa_measure import rects; rects(html, w, h, [".dot", ".pn", ".quando", ".rodape"])
"""
import json, re, subprocess, tempfile, pathlib

PROBE = """
<script>
window.addEventListener('load', function () {
  var out = [];
  document.querySelectorAll('*').forEach(function (el) {
    if (!el.className || typeof el.className !== 'string') return;
    var r = el.getBoundingClientRect();
    if (!r.width && !r.height) return;
    var leaf = el.children.length === 0;
    var ink = null;
    if (leaf && (el.textContent || '').trim()) {
      var rg = document.createRange();
      rg.selectNodeContents(el);
      var b = rg.getBoundingClientRect();
      ink = { x: Math.round(b.left), y: Math.round(b.top),
              w: Math.round(b.width), h: Math.round(b.height) };
    }
    out.push({ cls: el.className, tag: el.tagName.toLowerCase(),
               x: Math.round(r.left), y: Math.round(r.top),
               w: Math.round(r.width), h: Math.round(r.height),
               ink: ink,
               txt: (leaf ? (el.textContent || '').trim().slice(0, 60) : '') });
  });
  var pre = document.createElement('pre');
  pre.id = 'QA_RECTS';
  pre.textContent = JSON.stringify(out);
  document.body.appendChild(pre);
});
</script>
"""


def rects(html, w, h):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(html + PROBE)
        src = pathlib.Path(f.name)
    try:
        p = subprocess.run([
            "google-chrome-stable", "--headless", "--disable-gpu", "--no-sandbox",
            "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--window-size={w},{h}", "--virtual-time-budget=4000",
            "--dump-dom", f"file://{src}",
        ], check=True, capture_output=True, text=True)
    finally:
        src.unlink()
    m = re.search(r'<pre id="QA_RECTS">(.*?)</pre>', p.stdout, re.S)
    if not m:
        raise RuntimeError("probe nao rodou; stdout=%r" % p.stdout[:400])
    raw = m.group(1).replace("&quot;", '"').replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    return json.loads(raw)


def find(rs, cls_sub, txt_sub=None):
    hits = [r for r in rs if cls_sub in r["cls"] and (txt_sub is None or txt_sub in r["txt"])]
    return hits


def overlaps(a, b, folga=0):
    return not (a["x"] + a["w"] + folga <= b["x"] or b["x"] + b["w"] + folga <= a["x"]
                or a["y"] + a["h"] + folga <= b["y"] or b["y"] + b["h"] + folga <= a["y"])
