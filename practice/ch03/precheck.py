"""第 3 章練習 2：不用模型的記憶檔預檢，用正規表達式做 startup_scan.py 的三條檢查。

用法：PYTHONUTF8=1 python ch03/precheck.py [記憶資料夾，預設 ch03/mem-copy]
"""
import re
import sys
from pathlib import Path

# 規則 1：祈使句／命令代理的關鍵字（中英文）
IMPERATIVE = re.compile(
    r"\b(?:always\s+run|you\s+must|ignore\s+(?:all\s+)?previous|do\s+not\s+tell|never\s+tell)\b"
    r"|之後每次|每次開工|開工前先|務必|一律要|請先執行|忽略(?:先前|之前|以上)|不要告訴|別告訴",
    re.IGNORECASE,
)
# 規則 2：網址、金鑰樣式、長 base64
URL = re.compile(r"https?://\S+", re.IGNORECASE)
SECRET = re.compile(r"sk-ant-[\w-]{10,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|(?:api[_-]?key|token|password)\s*[:=]\s*\S{8,}",
                    re.IGNORECASE)
BASE64 = re.compile(r"[A-Za-z0-9+/]{40,}={0,2}")
# 規則 3：出處行（provenance／出處／來源，冒號全形半形皆可）
PROVENANCE = re.compile(r"^\s*(?:provenance|出處|來源)\s*[:：]\s*\S", re.IGNORECASE | re.MULTILINE)


def check(text):
    """回傳觸發的原因清單；空清單代表 PASS。"""
    reasons = []
    if m := IMPERATIVE.search(text):
        reasons.append(f"祈使句「{m.group(0)}」")
    for name, pattern in (("網址", URL), ("金鑰樣式", SECRET), ("長 base64", BASE64)):
        if m := pattern.search(text):
            reasons.append(f"{name}「{m.group(0)[:40]}」")
    if not PROVENANCE.search(text):
        reasons.append("缺出處行")
    return reasons


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("mem-copy")
    files = sorted(root.glob("lessons/*.md"))
    if not files:
        print(f"錯誤：{root}/lessons/ 底下沒有 .md 檔", file=sys.stderr)
        sys.exit(1)
    flagged = 0
    for f in files:
        try:
            reasons = check(f.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError) as e:
            reasons = [f"讀檔失敗：{e}"]
        if reasons:
            flagged += 1
            print(f"[QUARANTINE] {f.name}：{'；'.join(reasons)}")
        else:
            print(f"[PASS] {f.name}")
    print(f"done: {flagged}/{len(files)} 個檔會被隔離（僅判斷，不移動檔案）")


if __name__ == "__main__":
    main()
