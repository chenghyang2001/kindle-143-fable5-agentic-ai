"""第 3 章練習 1：攻擊記憶工具處理器的防護。

用法：
  PYTHONUTF8=1 python ch03/test_memory_guard.py          # 測原版 fable5/memory/memory_tool_handler.py
  PYTHONUTF8=1 python ch03/test_memory_guard.py --fixed  # 測修正版 ch03/handler_fixed.py
"""
import importlib
import shutil
import sys
from pathlib import Path

CH03 = Path(__file__).resolve().parent
PRACTICE = CH03.parent
sys.path.insert(0, str(PRACTICE / "fable5"))
sys.path.insert(0, str(CH03))

USE_FIXED = "--fixed" in sys.argv
h = importlib.import_module("handler_fixed" if USE_FIXED else "memory.memory_tool_handler")

# 第一件事：把根目錄改到 ch03/，絕不寫進 fable5/memory/memories
h.ROOT = (CH03 / ("memories_fixed" if USE_FIXED else "memories")).resolve()
shutil.rmtree(h.ROOT, ignore_errors=True)  # 每次重跑從乾淨狀態開始
h.ROOT.mkdir(parents=True)

CAP = h.MAX_FILE_BYTES
results = []


def run(cmd):
    """呼叫 handle()；例外也當成一種結果回傳，方便比對。"""
    try:
        return "ok", h.handle(cmd)
    except Exception as e:  # noqa: BLE001 — 這裡就是要觀察任何例外
        return "raised", f"{type(e).__name__}: {e}"


def is_blocked(outcome):
    kind, msg = outcome
    return kind == "raised" or str(msg).startswith("error")


def report(name, expected, actual, passed):
    results.append(passed)
    print(f"情境：{name}\n  預期：{expected}\n  實際：{actual}\n  是否符合：{'✅ 符合' if passed else '❌ 不符合'}\n")


def size_of(rel):
    f = h.ROOT / rel
    return f.stat().st_size if f.exists() else None


def main():
    print(f"受測模組：{h.__name__}（{Path(h.__file__).name}）")
    print(f"記憶根目錄：{h.ROOT}")
    print(f"大小上限 MAX_FILE_BYTES = {CAP:,} bytes\n")

    # 1. 正常 create → view
    r1 = run({"command": "create", "path": "/memories/lessons/a.md", "file_text": "第一課：先看 stop_reason\n"})
    r2 = run({"command": "view", "path": "/memories/lessons/a.md"})
    report("1. 正常 create 再 view /memories/lessons/a.md",
           "create 成功，view 讀回同樣內容",
           f"create → {r1[1]}；view → {r2[1]!r}",
           r1[0] == "ok" and r2 == ("ok", "第一課：先看 stop_reason\n"))

    # 2. 路徑逃逸
    r = run({"command": "view", "path": "/memories/../../secret.txt"})
    report("2. /memories/../../secret.txt 路徑逃逸", "被擋下（ValueError 或 error）", f"{r[0]} → {r[1]}", is_blocked(r))

    # 3. Windows 絕對路徑（只 view，不寫）
    r = run({"command": "view", "path": r"C:\Windows\win.ini"})
    report(r"3. Windows 絕對路徑 C:\Windows\win.ini（view）", "被擋下，不能讀到系統檔",
           f"{r[0]} → {str(r[1])[:120]}", is_blocked(r))

    # 4. 超過上限的中文 create
    over_chars = CAP // 3 + 1  # 中文 UTF-8 一字 3 bytes
    big_zh = "記" * over_chars
    print(f"（計算：{CAP:,} ÷ 3 = {CAP / 3:,.2f}，所以 {CAP // 3:,} 字 = {CAP // 3 * 3:,} bytes 還在上限內，"
          f"{over_chars:,} 字 = {len(big_zh.encode()):,} bytes 就超過）\n")
    r = run({"command": "create", "path": "/memories/big.md", "file_text": big_zh})
    report(f"4. create {over_chars:,} 個中文字（{len(big_zh.encode()):,} bytes）",
           "被拒絕，不寫檔", f"{r[1]}；檔案大小：{size_of('big.md')}", is_blocked(r) and size_of("big.md") is None)

    # 5. 小檔 → str_replace 成超大字串
    run({"command": "create", "path": "/memories/small.md", "file_text": "PLACEHOLDER\n"})
    r = run({"command": "str_replace", "path": "/memories/small.md", "old_str": "PLACEHOLDER", "new_str": big_zh})
    sz = size_of("small.md")
    report("5. 小檔用 str_replace 換成超大字串", f"被拒絕，檔案維持 ≤ {CAP:,} bytes",
           f"{r[1]}；檔案大小：{sz:,} bytes", is_blocked(r) and sz <= CAP)

    # 6. 小檔 → insert 超大字串
    run({"command": "create", "path": "/memories/small2.md", "file_text": "第一行\n第二行\n"})
    r = run({"command": "insert", "path": "/memories/small2.md", "insert_line": 1, "insert_text": big_zh + "\n"})
    sz = size_of("small2.md")
    report("6. 小檔用 insert 插入超大字串", f"被拒絕，檔案維持 ≤ {CAP:,} bytes",
           f"{r[1]}；檔案大小：{sz:,} bytes", is_blocked(r) and sz <= CAP)

    # 7. rename 逃出根目錄
    outside = (h.ROOT.parent / "outside.md")
    outside.unlink(missing_ok=True)
    r = run({"command": "rename", "path": "/memories/lessons/a.md", "new_path": "/memories/../outside.md"})
    report("7. rename 到 /memories/../outside.md", "被擋下，根目錄外不出現 outside.md",
           f"{r[0]} → {r[1]}；根目錄外 outside.md 存在：{outside.exists()}",
           is_blocked(r) and not outside.exists())

    # 8. 額外：換行符膨脹（Windows 文字模式會把 LF 寫成 CRLF，檢查的是編碼前的大小）
    newline_text = "a\n" * (CAP // 2 - 5)  # 編碼後 31,990 bytes，檢查時在上限內
    r = run({"command": "create", "path": "/memories/lines.md", "file_text": newline_text})
    sz = size_of("lines.md")
    report(f"8.（額外）create {len(newline_text.encode()):,} bytes、{newline_text.count(chr(10)):,} 個換行的內容",
           f"寫入成功且磁碟上 ≤ {CAP:,} bytes", f"{r[1]}；磁碟大小：{sz:,} bytes",
           r[0] == "ok" and sz is not None and sz <= CAP)

    print(f"總結：{sum(results)}/{len(results)} 個情境符合預期")


if __name__ == "__main__":
    main()
