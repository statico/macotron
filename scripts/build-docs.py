#!/usr/bin/env python3
"""Build site/docs/*.html from the fragments in site/docs/src.

Each fragment is the body of one page and starts with a metadata comment:

    <!-- title: macotron.clipboard
         summary: Read and write the pasteboard, and watch it change.
         group: API -->

Groups are Guide, Features, and API. Guide and Features pages may add
`order: N` to sort ahead of the alphabetical rest. The output is committed, so
Vercel serves it without running this script.

Run with --check to fail when a macotron.* namespace in macotron.d.ts has no
page, or a /docs/ link points at a page that does not exist.
"""
import html
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "site/docs/src"
OUT = ROOT / "site/docs"
DTS = ROOT / "Sources/Macotron/Resources/macotron.d.ts"
SITE = "https://macotron.statico.io"
GROUPS = ["Guide", "Features", "API"]

# Members of `macotron` documented together on one page instead of their own.
CORE = {"on", "off", "command", "alert", "confirm", "prompt", "log", "sleep", "every", "at",
        "checks", "settings", "version", "plugin", "module", "requirePermissions", "config", "flash"}


def parse(path):
    text = path.read_text()
    m = re.match(r"\s*<!--(.*?)-->\s*", text, re.S)
    if not m:
        sys.exit(f"{path}: missing metadata comment")
    meta = dict(re.findall(r"^\s*(\w+):\s*(.+?)\s*$", m.group(1), re.M))
    for key in ("title", "summary", "group"):
        if key not in meta:
            sys.exit(f"{path}: metadata needs {key}")
    if meta["group"] not in GROUPS:
        sys.exit(f"{path}: group must be one of {GROUPS}")
    return {
        "slug": path.stem,
        "title": meta["title"],
        "summary": meta["summary"],
        "group": meta["group"],
        "order": int(meta.get("order", 1000)),
        "body": highlight_blocks(anchor_headings(text[m.end():])),
    }


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"<[^>]+>", "", text).lower()).strip("-")


def anchor_headings(body):
    """Give every h2 and h3 an id so sections can be linked."""
    def add(m):
        tag, attrs, inner = m.group(1), m.group(2), m.group(3)
        if "id=" in attrs:
            return m.group(0)
        return f'<{tag}{attrs} id="{slugify(inner)}">{inner}</{tag}>'
    return re.sub(r"<(h[23])([^>]*)>(.*?)</\1>", add, body, flags=re.S)


# Same tokens as site.js colors the plugin finder with.
TOKEN = re.compile(r"(//.*$|/\*[\s\S]*?\*/|`(?:\\.|[^`\\])*`|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')", re.M)
KEYWORDS = re.compile(r"\b(const|let|var|function|return|if|else|for|of|async|await|new|typeof|true|false|null|undefined)\b")


def color_js(chunk):
    chunk = KEYWORDS.sub(r'<span class="tok-kw">\1</span>', chunk)
    chunk = re.sub(r"\b(macotron)\b", r'<span class="tok-fn">\1</span>', chunk)
    return re.sub(r"(?<![\w#-])(\d+(?:\.\d+)?)\b", r'<span class="tok-num">\1</span>', chunk)


def highlight(code):
    """`code` is already HTML-escaped, as it is inside the fragment."""
    out, last = [], 0
    for m in TOKEN.finditer(code):
        out.append(color_js(code[last:m.start()]))
        cls = "tok-cmt" if m.group(0).startswith("/") else "tok-str"
        out.append(f'<span class="{cls}">{m.group(0)}</span>')
        last = m.end()
    out.append(color_js(code[last:]))
    return "".join(out)


def highlight_blocks(body):
    return re.sub(
        r'(<pre><code class="language-javascript">)(.*?)(</code></pre>)',
        lambda m: m.group(1) + highlight(m.group(2)) + m.group(3),
        body, flags=re.S)


def head(title, summary, url, crumbs):
    items = ",\n      ".join(
        f'{{ "@type": "ListItem", "position": {i + 1}, "name": "{html.escape(n)}", "item": "{SITE}{u}" }}'
        for i, (n, u) in enumerate(crumbs))
    t, s = html.escape(title), html.escape(summary)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{t} · Macotron</title>
  <meta name="description" content="{s}">
  <meta property="og:title" content="{t} · Macotron">
  <meta property="og:description" content="{s}">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="Macotron">
  <meta property="og:url" content="{SITE}{url}">
  <meta property="og:image" content="{SITE}/og.png">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="canonical" href="{SITE}{url}">
  <link rel="icon" href="/icon.png">
  <link rel="stylesheet" href="/site.css">
  <script src="/head.js"></script>
  <script type="application/ld+json">
  {{
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "itemListElement": [
      {items}
    ]
  }}
  </script>
</head>
"""


def header():
    return (ROOT / "site/header.html").read_text()


def footer():
    return """  <footer>
    <p><a href="https://github.com/statico/macotron">github.com/statico/macotron</a></p>
    <p><a href="/docs/">Docs</a> · <a href="/glossary.html">Glossary</a></p>
  </footer>
  <script src="/common.js"></script>
</body>
</html>
"""


def sort_pages(pages):
    return sorted(pages, key=lambda p: (GROUPS.index(p["group"]), p["order"], p["title"].lower()))


def nav(pages, current):
    parts = ['<nav class="docs-nav" aria-label="Documentation">',
             f'<a href="/docs/"{" aria-current=\"page\"" if current is None else ""}>Overview</a>']
    for group in GROUPS:
        members = [p for p in pages if p["group"] == group]
        if not members:
            continue
        parts.append(f"<p>{group}</p>")
        for p in members:
            cur = ' aria-current="page"' if current == p["slug"] else ""
            parts.append(f'<a href="/docs/{p["slug"]}.html"{cur}>{html.escape(p["title"])}</a>')
    parts.append("</nav>")
    return "\n".join(parts)


def page_html(page, pages):
    url = f"/docs/{page['slug']}.html"
    crumbs = [("Home", "/"), ("Docs", "/docs/"), (page["title"], url)]
    return (head(page["title"], page["summary"], url, crumbs) + "<body>\n" + header() +
            f'  <main class="docs">\n{nav(pages, page["slug"])}\n<article class="doc">\n{page["body"].strip()}\n</article>\n  </main>\n' +
            footer())


def index_html(pages):
    body = ['<h1>Documentation</h1>',
            '<p class="lede">How Macotron works, what it can do, and every <code>macotron.*</code> call a plugin can make.</p>']
    for group in GROUPS:
        members = [p for p in pages if p["group"] == group]
        if not members:
            continue
        body.append(f'<h2 id="{group.lower()}">{group}</h2>\n<dl class="doc-index">')
        for p in members:
            body.append(f'<dt><a href="/docs/{p["slug"]}.html">{html.escape(p["title"])}</a></dt>'
                        f'<dd>{html.escape(p["summary"])}</dd>')
        body.append("</dl>")
    crumbs = [("Home", "/"), ("Docs", "/docs/")]
    return (head("Documentation", "Guides, features, and the full macotron.* plugin API.", "/docs/", crumbs) +
            "<body>\n" + header() +
            f'  <main class="docs">\n{nav(pages, None)}\n<article class="doc">\n' + "\n".join(body) +
            "\n</article>\n  </main>\n" + footer())


def write_sitemap(pages):
    today = date.today().isoformat()
    urls = ["/", "/glossary.html", "/AGENTS.md", "/docs/"] + [f"/docs/{p['slug']}.html" for p in pages]
    entries = "\n".join(f"  <url>\n    <loc>{SITE}{u}</loc>\n    <lastmod>{today}</lastmod>\n  </url>" for u in urls)
    (ROOT / "site/sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + entries + "\n</urlset>\n")


def write_llms(pages):
    lines = ["# Macotron", "", "Native macOS host for JavaScript plugins.", "", "## Read these", "",
             "- [Home](/)", "- [Docs](/docs/)", "- [Glossary](/glossary.html)", "- [AGENTS.md](/AGENTS.md)",
             "- [Sitemap](/sitemap.xml)"]
    for group in GROUPS:
        members = [p for p in pages if p["group"] == group]
        if members:
            lines += ["", f"## {group}", ""]
            lines += [f"- [{p['title']}](/docs/{p['slug']}.html): {p['summary']}" for p in members]
    (ROOT / "site/llms.txt").write_text("\n".join(lines) + "\n")


def namespaces():
    text = DTS.read_text()
    block = text[text.index("declare const macotron"):]
    block = block[:block.index("\n};")]
    return sorted(set(re.findall(r"^    (\w+)[:(]", block, re.M)) - CORE)


def check(pages):
    errors = []
    slugs = {p["slug"] for p in pages}
    for ns in namespaces():
        if f"api-{ns}" not in slugs:
            errors.append(f"macotron.{ns} has no page (site/docs/src/api-{ns}.html)")
    if "api-core" not in slugs:
        errors.append("the core macotron.* calls have no page (site/docs/src/api-core.html)")
    for p in pages:
        for link in re.findall(r'href="/docs/([\w-]+)\.html', p["body"]):
            if link not in slugs:
                errors.append(f"{p['slug']}: links to missing /docs/{link}.html")
    return errors


def main():
    pages = sort_pages([parse(p) for p in sorted(SRC.glob("*.html"))])
    if "--check" in sys.argv:
        errors = check(pages)
        print("\n".join(errors) or f"{len(pages)} pages, every namespace documented")
        sys.exit(1 if errors else 0)
    for page in pages:
        (OUT / f"{page['slug']}.html").write_text(page_html(page, pages))
    (OUT / "index.html").write_text(index_html(pages))
    write_sitemap(pages)
    write_llms(pages)
    print(f"Wrote {len(pages)} pages to site/docs")


if __name__ == "__main__":
    main()
