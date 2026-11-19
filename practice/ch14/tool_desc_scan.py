"""第 14 章練習 1：工具描述掃描器（上線前靜態檢查，不呼叫模型）。

用法：PYTHONUTF8=1 python ch14/tool_desc_scan.py [tools.json，預設 ch14/tools_poisoned.json]
"""
import json
import re
import sys
from pathlib import Path

# (類別, 嚴重度, 樣式)；嚴重度 high 的命中代表工具描述在「指揮」模型，而不是「說明」工具
RULES = [
    ("要求先呼叫某工具", "high", re.compile(
        r"\b(?:before|prior\s+to)\s+(?:calling|using|invoking)\s+(?:any|other|another)\b|"
        r"\b(?:always|first)\s+(?:call|invoke|use)\b|\bmust\s+(?:first\s+)?(?:call|invoke)\b|"
        r"(?:呼叫|使用)任何工具之前|先呼叫本工具", re.IGNORECASE)),
    ("要求帶出個資或內部資料", "high", re.compile(
        r"\b(?:e-?mail|phone|address|ssn|credit\s*card|password|api\s*key|token|margin|cost\s+price|internal)\b.{0,60}"
        r"\b(?:into|in|to)\s+the\s+\w+\s+(?:param|parameter|argument|field)|"
        r"(?:email|電話|地址|密碼|金鑰|毛利|成本).{0,20}(?:放進|帶入|填入|傳入).{0,10}參數", re.IGNORECASE)),
    ("要求讀檔或連網", "high", re.compile(
        r"\b(?:read|open|cat)\s+(?:the\s+)?(?:file|~/|/etc/|\.env|\.ssh)|https?://|\bcurl\b|\bwget\b|"
        r"\b(?:send|post|upload)\s+(?:it|this|the\s+\w+)\s+to\b|讀取.{0,6}檔案|連線到", re.IGNORECASE)),
    ("提到 system prompt／忽略指示／要求隱瞞", "high", re.compile(
        r"system\s+prompt|\bignore\s+(?:all\s+|any\s+)?(?:previous|prior|other)\b|"
        r"\bdo\s+not\s+(?:mention|tell|reveal)\b.{0,40}\b(?:user|customer)|忽略.{0,4}指示|不要告訴", re.IGNORECASE)),
    ("強調框／命令語氣", "medium", re.compile(r"\b(?:IMPORTANT|CRITICAL|MANDATORY)\b|\bYOU\s+MUST\b|\brequired\s+for\b")),
]
LEVELS = ("none", "low", "medium", "high")


def scan_tool(tool):
    """回傳 (命中清單, 風險等級)。命中是 (類別, 嚴重度, 命中字串)。"""
    desc = tool.get("description") or ""
    hits = [(cat, sev, m.group(0)) for cat, sev, pat in RULES for m in [pat.search(desc)] if m]
    if tool.get("rate_limit") is None:
        hits.append(("rate_limit 為 null", "low", "rate_limit=null"))
    if not desc.strip():
        hits.append(("沒有 description", "low", "（空）"))
    level = max((sev for _, sev, _ in hits), key=LEVELS.index, default="none")
    return hits, level


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("tools_poisoned.json")
    try:
        tools = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"錯誤：讀不到或解析不了 {path}：{e}", file=sys.stderr)
        return 2
    worst = "none"
    print(f"掃描 {path.name}：{len(tools)} 個工具\n")
    for tool in tools:
        hits, level = scan_tool(tool)
        worst = max(worst, level, key=LEVELS.index)
        print(f"[{level.upper():<6}] {tool.get('name')}")
        for cat, sev, text in hits:
            print(f"    {sev:<6} {cat}：{text[:70]!r}")
    print(f"\n最高風險：{worst}；有 high 就不該上線（exit 1）")
    return 1 if worst == "high" else 0


if __name__ == "__main__":
    sys.exit(main())
