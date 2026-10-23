"""Copies site/ into a host's public folder under a URL prefix, with absolute asset paths and share metadata.

Usage: python3 scripts/site_deploy.py <public-dir> --prefix /365AImaster --origin https://724.fund
"""
import argparse
import re
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("public_dir", type=Path)
parser.add_argument("--prefix", default="/365AImaster")
parser.add_argument("--origin", default="https://724.fund")
args = parser.parse_args()

site = Path(__file__).resolve().parent.parent / "site"
prefix = args.prefix.rstrip("/")
target = args.public_dir / prefix.lstrip("/")
if target.exists():
    shutil.rmtree(target)
shutil.copytree(site / "assets", target / "assets")
pages = {"zh-CN": prefix, "en": prefix + "/en"}


def rewrite(html: str, page: str, image: str) -> str:
    html = re.sub(r'(href|src)="(?:\.\./)?assets/', rf'\1="{prefix}/assets/', html)
    html = html.replace('href="../index.html"', f'href="{pages["zh-CN"]}"')
    html = html.replace('href="en/index.html"', f'href="{pages["en"]}"')
    html = html.replace('class="brand" href="./"', f'class="brand" href="{page}"')
    html = re.sub(r'<link rel="alternate" hreflang="([^"]+)" href="[^"]*">',
                  lambda m: f'<link rel="alternate" hreflang="{m.group(1)}" href="{args.origin}{pages[m.group(1)]}">', html)
    meta = (f'<link rel="canonical" href="{args.origin}{page}">\n'
            f'<meta property="og:url" content="{args.origin}{page}">\n'
            '<meta property="og:type" content="website">\n'
            f'<meta property="og:image" content="{args.origin}{prefix}/assets/img/{image}">\n'
            '<meta name="twitter:card" content="summary_large_image">\n')
    return html.replace('<link rel="alternate"', meta + '<link rel="alternate"', 1)


for source, page, image in (("index.html", pages["zh-CN"], "share-zh.png"), ("en/index.html", pages["en"], "share-en.png")):
    out = target / source
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(rewrite((site / source).read_text(encoding="utf-8"), page, image), encoding="utf-8")

leftover = [p for p in target.rglob("*.html") if re.search(r'(href|src)="(\.\./|assets/|en/index|\./")', p.read_text(encoding="utf-8"))]
assert not leftover, f"relative links left in {leftover}"
print(f"{target} ready: {sum(1 for p in target.rglob('*') if p.is_file())} files")
