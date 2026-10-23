"""Builds a private claude.ai artifact preview of site/: the zh page body without its document shell, plus files."""
import re
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "site"
out = Path(sys.argv[1])
if out.exists():
    shutil.rmtree(out)
shutil.copytree(root, out)
page = (root / "index.html").read_text(encoding="utf-8")
head = re.search(r"<head>(.*?)</head>", page, re.S).group(1)
body = re.search(r"<body>(.*?)</body>", page, re.S).group(1)
head = re.sub(r'<meta charset="utf-8">\s*|<meta name="viewport"[^>]*>\s*', "", head)
head = re.sub(r"<title>.*?</title>", "<title>365 AI Master 官网</title>", head)
(out / "index.html").write_text(head.strip() + "\n" + body.strip() + "\n", encoding="utf-8")
print(sorted(str(p.relative_to(out)) for p in out.rglob("*") if p.is_file()))
