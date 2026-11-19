"""修正版記憶工具處理器（複製自 fable5/memory/memory_tool_handler.py，原檔未修改）。

和原版的差別（每處都標了「修正」）：
1. 大小上限套用在所有寫入指令的「最終內容」上（create／str_replace／insert），不只 create。
2. 以 bytes 寫檔，不經過 Windows 文字模式的 LF→CRLF 轉換，磁碟大小＝檢查時的大小。
3. 路徑前綴嚴格比對：只接受 "/memories" 或 "/memories/..."。
4. 防護失敗回傳 "error: ..." 字串給模型，而不是丟例外讓整個迴圈中斷。
5. rename 不覆蓋既有檔案；insert_line 檢查範圍。
"""
from pathlib import Path

ROOT = Path(__file__).with_name("memories").resolve()
MAX_FILE_BYTES = 32_000


def _resolve(raw):
    # 修正 3：原版 removeprefix 會讓 "/memoriesX/a" 變成 "X/a"，前綴必須完整
    if raw != "/memories" and not raw.startswith("/memories/"):
        raise ValueError(f"path must start with /memories/: {raw}")
    rel = raw[len("/memories"):].lstrip("/")
    path = (ROOT / rel).resolve()
    if ROOT != path and ROOT not in path.parents:
        raise ValueError(f"path escapes memory root: {raw}")
    return path


def _write_capped(p, text):
    """修正 1＋2：所有寫入都經過這裡，用最終內容的 UTF-8 bytes 判斷並原樣寫出。"""
    data = text.encode("utf-8")
    if len(data) > MAX_FILE_BYTES:
        raise ValueError(f"file would be {len(data):,} bytes, over the {MAX_FILE_BYTES:,}-byte cap; distill it")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)


def _read(p):
    return p.read_bytes().decode("utf-8")


def _dispatch(cmd):
    p = _resolve(cmd.get("path", "/memories"))
    c = cmd["command"]
    if c == "view":
        if p.is_dir():
            return "\n".join(sorted(x.name for x in p.iterdir()))
        return _read(p)
    if c == "create":
        _write_capped(p, cmd["file_text"])
        return f"created {p.name}"
    if c == "str_replace":
        body = _read(p)
        if cmd["old_str"] not in body:
            return "error: old_str not found"
        _write_capped(p, body.replace(cmd["old_str"], cmd["new_str"], 1))
        return f"edited {p.name}"
    if c == "insert":
        lines = _read(p).splitlines(keepends=True)
        line_no = cmd["insert_line"]
        if not 0 <= line_no <= len(lines):  # 修正 5
            return f"error: insert_line {line_no} out of range 0..{len(lines)}"
        lines.insert(line_no, cmd["insert_text"])
        _write_capped(p, "".join(lines))
        return f"inserted into {p.name}"
    if c == "delete":
        if not p.is_file():
            return f"error: not a file: {p.name}"
        p.unlink()
        return f"deleted {p.name}"
    if c == "rename":
        dest = _resolve(cmd["new_path"])
        if dest.exists():  # 修正 5：不默默覆蓋另一課
            return f"error: destination exists: {dest.name}"
        dest.parent.mkdir(parents=True, exist_ok=True)
        p.rename(dest)
        return f"renamed to {dest.name}"
    return f"error: unknown command {c}"


def handle(cmd):
    """修正 4：防護與 I/O 錯誤都轉成 tool_result 文字，迴圈可以繼續、模型也看得到原因。"""
    try:
        return _dispatch(cmd)
    except (ValueError, OSError, KeyError) as e:
        return f"error: {e}"


if __name__ == "__main__":
    assert handle({"command": "view", "path": "/memories/../../etc/passwd"}).startswith("error")
    assert handle({"command": "view", "path": "/memoriesX/a"}).startswith("error")
    print("ok: traversal and prefix guards hold")
