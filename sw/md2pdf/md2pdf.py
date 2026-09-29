"""
md2pdf - документ Markdown (.md) в PDF формата A4. PDF кладётся рядом с .md.

    py sw/md2pdf/md2pdf.py hw/info/performance_roadmap.md hw/info/interrupts.md

Путь: Markdown -> HTML (python-markdown: таблицы, блоки кода, якоря разделов) -> PDF печатью
в Edge или Chrome без окна (--headless --print-to-pdf).
Документы проекта написаны для GitHub, а Python-Markdown строже к спискам, поэтому перед
разбором списки приводятся к его правилам (см. gfm_lists). Сами .md не меняются.
Ссылки на другие файлы репозитория в PDF не работают, поэтому остаются простым текстом;
ссылки на разделы документа (#якорь) и адреса http(s) сохраняются.
Нужно: Python 3 с пакетом markdown (py -m pip install markdown), Microsoft Edge или Google Chrome.
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

try:
    import markdown
    from markdown.extensions.toc import TocExtension, slugify_unicode
except ImportError:
    sys.exit("Нет пакета markdown: py -m pip install markdown")

sys.stdout.reconfigure(encoding="utf-8")  #Вывод в UTF-8, как у остальных утилит sw/ (консоль Eclipse, Git Bash)

BROWSERS = [r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
            r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
            r"C:\Program Files\Google\Chrome\Application\chrome.exe"]

CSS = """
@page { size: A4; margin: 16mm 14mm 16mm 14mm; }
body { font-family: "Segoe UI", Arial, sans-serif; font-size: 10pt; line-height: 1.45; color: #1a1a1a; }
h1 { font-size: 19pt; border-bottom: 2px solid #2b5797; padding-bottom: 4px; color: #2b5797; }
h2 { font-size: 14pt; color: #2b5797; border-bottom: 1px solid #c8d3e6; padding-bottom: 2px; margin-top: 22px;
     break-after: avoid; }
h3 { font-size: 11.5pt; color: #1f3f73; margin-top: 16px; break-after: avoid; }
p, li { orphans: 3; widows: 3; }
code { font-family: Consolas, "Courier New", monospace; font-size: 8.8pt; background: #f1f3f6; padding: 0 2px; border-radius: 2px; }
pre { background: #f5f7fa; border: 1px solid #d9dee6; border-radius: 3px; padding: 7px 9px; font-size: 8.4pt;
      line-height: 1.3; white-space: pre-wrap; break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 8.4pt; }
table { border-collapse: collapse; margin: 8px 0; font-size: 8.8pt; width: auto; }
th, td { border: 1px solid #c3cad6; padding: 3px 6px; vertical-align: top; }
th { background: #e8eef7; }
tr { break-inside: avoid; }
blockquote { border-left: 3px solid #c8d3e6; margin: 8px 0; padding: 2px 10px; color: #444; background: #fafbfd; }
a { color: #2b5797; text-decoration: none; }
del { color: #888; }
.src { font-size: 8pt; color: #777; margin-bottom: 10px; }
"""

LIST = re.compile(r"^( *)([-*+]|\d+\.) +")


def gfm_lists(text):
    """Списки в стиле GitHub -> в понятные Python-Markdown:
    - перед пунктом, который идёт сразу после текста (абзаца или продолжения пункта), - пустая строка;
    - отступ вложенных пунктов и продолжений пункта - 4 пробела на уровень (в GitHub хватает 2-3)."""
    out, stack, fence, prev = [], [], False, ""   # stack: (отступ маркера, отступ текста пункта) в исходнике
    for line in text.split("\n"):
        if line.strip().startswith("```") and not line.startswith(" "):
            fence = not fence
            if fence:
                stack = []
            out.append(line); prev = line
            continue
        if fence or not line.strip():
            out.append(line); prev = line
            continue
        n = len(line) - len(line.lstrip(" "))
        m = LIST.match(line)
        while stack and n < stack[-1][1]:       # строка вне текста текущего пункта (в т.ч. соседний пункт)
            stack.pop()
        if m:
            if prev.strip() and not LIST.match(prev):
                out.append("")
            out.append(" " * (4 * len(stack)) + line.lstrip(" "))
            stack.append((n, len(m.group(0))))
        elif stack:                             # продолжение пункта
            out.append(" " * (4 * len(stack)) + line.lstrip(" "))
        else:
            out.append(line)
        prev = line
    return "\n".join(out)


def find_browser(explicit):
    for b in ([explicit] if explicit else []) + BROWSERS + [shutil.which("msedge") or "", shutil.which("chrome") or ""]:
        if b and os.path.exists(b):
            return b
    sys.exit("Не найден Microsoft Edge или Google Chrome: укажите путь ключом --browser")


def to_html(md_path, repo_root):
    text = gfm_lists(md_path.read_text(encoding="utf-8"))
    body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists",
                                               TocExtension(slugify=slugify_unicode, toc_depth="2-3")])
    body = re.sub(r"~~(.+?)~~", r"<del>\1</del>", body)
    body = re.sub(r'<a href="(?!#|https?:)[^"]*">(.*?)</a>', r"\1", body)
    title = re.search(r"<h1[^>]*>(.*?)</h1>", body)
    try:
        src = md_path.relative_to(repo_root).as_posix()
    except ValueError:
        src = md_path.name
    return (f'<!doctype html><html lang="ru"><head><meta charset="utf-8">'
            f'<title>{title.group(1) if title else md_path.stem}</title><style>{CSS}</style></head><body>'
            f'<div class="src">askoRV32 · {src}</div>{body}</body></html>')


def main():
    ap = argparse.ArgumentParser(description="Документы Markdown в PDF (A4) через Edge/Chrome")
    ap.add_argument("files", nargs="+", help="файлы .md; PDF создаётся рядом")
    ap.add_argument("--browser", help="путь к msedge.exe или chrome.exe")
    ap.add_argument("--html", action="store_true", help="сохранить и промежуточный .html рядом с .md")
    a = ap.parse_args()
    browser = find_browser(a.browser)
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for f in a.files:
            md = pathlib.Path(f).resolve()
            if not md.exists():
                print(f"Нет файла: {f}"); ok = False; continue
            page = to_html(md, repo_root)
            html = (md.with_suffix(".html") if a.html else pathlib.Path(tmp) / (md.stem + ".html"))
            html.write_text(page, encoding="utf-8")
            pdf = md.with_suffix(".pdf")
            r = subprocess.run([browser, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                                "--print-to-pdf-no-header", f"--print-to-pdf={pdf}", html.as_uri()],
                               capture_output=True, text=True, timeout=300)
            if pdf.exists() and pdf.stat().st_size > 0:
                print(f"{pdf}  ({pdf.stat().st_size // 1024} кБайт)")
            else:
                print(f"Ошибка печати {md.name}: {r.stderr.strip()[-300:]}"); ok = False
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
