"""Convert a Sakinah plan markdown file into a styled PDF.

Usage:
    python md_to_pdf.py [md_path] [out_pdf]
    python md_to_pdf.py    # uses the original emotion-detection plan defaults
"""
import sys
from pathlib import Path

import markdown
from xhtml2pdf import pisa

DEFAULT_MD = Path(r"C:\Users\tqamu\.claude\plans\ancient-knitting-shamir.md")
DEFAULT_OUT = Path(r"d:\merge fyp\Sakinah_Emotion_Detection_Plan.pdf")

MD_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_MD
OUT_PATH = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUT

CSS = """
@page { size: A4; margin: 18mm 16mm; }
body { font-family: "Segoe UI", Arial, sans-serif; font-size: 10.5pt; color: #1f2937; line-height: 1.5; }
h1 { color: #15803d; border-bottom: 2px solid #15803d; padding-bottom: 6px; font-size: 22pt; margin-top: 0; }
h2 { color: #15803d; border-bottom: 1px solid #d1d5db; padding-bottom: 4px; font-size: 16pt; margin-top: 18pt; }
h3 { color: #166534; font-size: 13pt; margin-top: 14pt; }
h4 { color: #166534; font-size: 11pt; }
code { background: #f3f4f6; padding: 1px 4px; border-radius: 3px; font-family: "Consolas", monospace; font-size: 9.5pt; color: #be123c; }
pre { background: #f9fafb; border: 1px solid #e5e7eb; padding: 10px; border-radius: 4px; font-family: "Consolas", monospace; font-size: 8.5pt; line-height: 1.35; white-space: pre-wrap; }
pre code { background: transparent; color: #1f2937; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 10pt 0; font-size: 9.5pt; }
th, td { border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; vertical-align: top; }
th { background: #f0fdf4; color: #14532d; font-weight: 600; }
ul, ol { margin: 6pt 0 6pt 18pt; }
li { margin: 2pt 0; }
blockquote { border-left: 3px solid #15803d; padding: 4pt 10pt; color: #4b5563; background: #f9fafb; margin: 8pt 0; }
a { color: #15803d; text-decoration: none; }
hr { border: none; border-top: 1px solid #d1d5db; margin: 14pt 0; }
strong { color: #14532d; }
"""

def convert():
    md_text = MD_PATH.read_text(encoding="utf-8")
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc", "sane_lists"],
    )
    full_html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>{CSS}</style></head>
<body>{html_body}</body></html>"""

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "wb") as f:
        result = pisa.CreatePDF(full_html, dest=f, encoding="utf-8")

    if result.err:
        print(f"ERROR: {result.err} errors during PDF generation", file=sys.stderr)
        sys.exit(1)
    print(f"OK: wrote {OUT_PATH}")

if __name__ == "__main__":
    convert()
