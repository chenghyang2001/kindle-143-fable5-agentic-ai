"""第 2 章練習 2：深度研究迴圈只跑一小段（拆題 1 ＋ 搜尋 1 ＋ 三票驗證 3 ＝ 5 次 claude -p）。"""
import json
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()
import deep_research.research_loop as rl  # noqa: E402

CH02 = PRACTICE / "ch02"
rl.MEMORY = CH02 / "claims.jsonl"  # 執行期寫檔改到 ch02/
QUESTION = "Claude Code 的 Skills 和 MCP 伺服器各適合什麼情境？"

# 包一層 ask：不增加呼叫次數，只把每次的 effort 與回應原文記下來，
# 因為 rl.verify 只回布林值，看不到三個投票者各自說了什麼。
_original_ask = rl.ask
call_log = []


def logged_ask(prompt, effort, tools=None, budget=None):
    text = _original_ask(prompt, effort, tools=tools, budget=budget)
    call_log.append({"effort": effort, "tools": bool(tools), "budget": budget, "text": text})
    return text


rl.ask = logged_ask


def main() -> None:
    print(f"[問題] {QUESTION}\n")

    angles = rl.decompose(QUESTION)
    if not angles:
        print("錯誤：拆題沒有拿到任何角度（可能拒答或空回應）", file=sys.stderr)
        sys.exit(1)
    print("== 步驟 1：拆出的角度 ==")
    for i, angle in enumerate(angles, 1):
        print(f"  {i}. {angle}")

    print(f"\n== 步驟 2：搜尋第一個角度 ==\n  角度：{angles[0]}")
    claims = rl.search_angle(QUESTION, angles[0])
    print(f"  拿到 {len(claims)} 條主張")
    for c in claims:
        print(f"  - {c.get('claim')}\n    來源：{c.get('source')}")
    if not claims:
        print("  搜尋回應原文：\n" + (call_log[-1]["text"] or "(None)"))
        sys.exit(1)

    claim = claims[0]
    print(f"\n== 步驟 3：三票驗證第一條主張 ==\n  主張：{claim['claim']}\n  來源：{claim['source']}")
    ok = rl.verify(claim)
    for n, entry in enumerate(call_log[-3:], 1):
        print(f"  投票者 {n}：{(entry['text'] or '(None／拒答)').strip()}")
    claim["verdict"] = "confirmed" if ok else "refuted"
    with rl.MEMORY.open("a", encoding="utf-8") as f:
        f.write(json.dumps(claim, ensure_ascii=False) + "\n")
    print(f"  結果：{claim['verdict']}（已附加寫入 {rl.MEMORY.name}）")

    print("\n== 每次呼叫的 effort ==")
    for n, entry in enumerate(call_log, 1):
        print(f"  {n}. effort={entry['effort']} web_search={entry['tools']} task_budget={entry['budget']}")
    print(f"claude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
