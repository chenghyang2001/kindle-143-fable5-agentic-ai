"""第 17 章練習 1：標準答案（逐字比對）vs 性質斷言。共 5 次 claude -p。"""
import json
import re
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()
import fable_scanner.canary as c  # noqa: E402  只取用 c._score，不執行 canary

FABLE = "claude-fable-5"
PROMPT_A = '用 JSON 回答：{"lang": 程式語言名稱, "reason": 一句理由}，題目：寫命令列小工具首選哪種語言？'
CASES_B = [
    {"id": "classify-low", "effort": "low",
     "prompt": "把這則錯誤分類成 bug、config、network 其中一個，只回一個英文小寫單字：connection refused on port 5432",
     "expect": {"contains": ["network"], "max_len": 12}},
    {"id": "explain-high", "effort": "high",
     "prompt": "用兩到三句話解釋為什麼資料庫遷移要先做向後相容的 schema 變更，再部署新版程式。",
     "expect": {"contains": ["相容"], "min_len": 40, "max_len": 400}},
    {"id": "format-default", "effort": None,
     "prompt": "把這三個詞依字母順序排好，用逗號分隔，不要其他文字：cherry, apple, banana",
     "expect": {"exact": "apple, banana, cherry"}},
]


def ask(prompt, effort=None):
    kw = {"output_config": {"effort": effort}} if effort else {}
    msg = claude_cli_client.Anthropic().messages.create(
        model=FABLE, max_tokens=500, messages=[{"role": "user", "content": prompt}], **kw)
    return "" if msg.stop_reason == "refusal" or not msg.content else msg.content[0].text


def props(text):
    """性質斷言：嚴格 json.loads、有 lang 與 reason、reason < 120 字元。回傳 [(名稱, 是否通過)]。"""
    try:
        obj = json.loads(text)
        parsed = isinstance(obj, dict)
    except json.JSONDecodeError:
        obj, parsed = {}, False
    reason = obj.get("reason") if parsed else None
    return [("能 json.loads", parsed),
            ("有 lang 與 reason", parsed and "lang" in obj and "reason" in obj),
            ("reason 長度 < 120", isinstance(reason, str) and len(reason) < 120)]


def show(text):
    return text.strip().replace("\n", "⏎")[:100]


def main():
    try:
        print(f"== (a) 同一提示詞送 2 次 ==\n提示詞：{PROMPT_A}")
        outs = [ask(PROMPT_A) for _ in range(2)]
        for i, t in enumerate(outs, 1):
            print(f"\n第 {i} 次原始輸出（前 100 字）：{show(t)}")
            for name, ok in props(t):
                print(f"  性質「{name}」：{'PASS' if ok else 'FAIL'}")
            fenced = re.sub(r"^```(?:json)?\s*|\s*```$", "", t.strip())
            if fenced != t.strip():
                print(f"  （補充：去掉 ``` 圍欄後再測 → {[ok for _, ok in props(fenced)]}）")
        print(f"\n逐字比對（第 2 次 == 第 1 次）：{'PASS' if outs[0] == outs[1] else 'FAIL'}"
              f"（長度 {len(outs[0])} vs {len(outs[1])}）")
        print(f"性質斷言兩次都全過：{'PASS' if all(ok for t in outs for _, ok in props(t)) else 'FAIL'}")

        print("\n== (b) 3 個提示詞各 1 次，用 c._score 打分 ==")
        for case in CASES_B:
            t = ask(case["prompt"], case["effort"])
            print(f"\n[{case['id']}] effort={case['effort'] or '預設（不送）'} expect={case['expect']}")
            print(f"  原始輸出（前 100 字）：{show(t)}  （{len(t)} 字元）")
            print(f"  c._score = {c._score(case['expect'], t):.0%}")
    except claude_cli_client.APIError as e:
        print(f"錯誤：{e}", file=sys.stderr)
        sys.exit(1)
    print(f"\nclaude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
