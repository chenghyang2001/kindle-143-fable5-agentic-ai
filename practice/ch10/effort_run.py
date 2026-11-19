"""第 10 章練習 1：同一任務不同 effort，量真實的 output_tokens（3＋2＝5 次 claude -p）。"""
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()
import effort.effort_router as er  # noqa: E402  不執行 main()，只用 run()

SUMMARIZE_PROMPT = (
    "Summarize this failed deploy log for the on-call channel.\n\n"
    "14:02 deploy billing-api v3.8.1 to prod started (canary 10%)\n"
    "14:04 canary pods CrashLoopBackOff: KeyError 'STRIPE_WEBHOOK_SECRET'\n"
    "14:05 auto-rollback triggered, traffic back to v3.8.0\n"
    "14:07 root cause: secret added to staging vault but not prod vault\n"
    "14:09 no customer-facing errors; deploy marked failed"
)
FLEET = [
    {"kind": "classify", "prompt": "Is this ticket a bug or a feature? Answer with one word. "
                                   "Ticket: 'App crashes when saving a draft with an emoji in the title.'"},
    {"kind": "summarize", "prompt": SUMMARIZE_PROMPT},
    {"kind": "audit", "prompt": "Write a brief threat assessment, 10 lines or fewer, of an AI agent that can "
                                "read support tickets and trigger production deploys."},
]


def direct(prompt, effort):
    """不經 effort_for()，直接指定 effort 送同一個提示詞。"""
    msg = claude_cli_client.Anthropic().messages.create(
        model=er.FABLE, max_tokens=2048, output_config={"effort": effort},
        messages=[{"role": "user", "content": prompt}],
    )
    return {"kind": "summarize（直接指定）", "effort": effort, "output_tokens": msg.usage.output_tokens,
            "chars": len(msg.content[0].text) if msg.content else 0}


def main():
    rows = []
    try:
        print("(a) er.run()：effort 由 effort_for() 決定")
        for task in FLEET:
            r = er.run(task)
            rows.append(r)
            print(f"  {r['kind']:<22} effort={r['effort']:<6} output_tokens={r['output_tokens']}")
        print("\n(b) 同一個 summarize 提示詞，直接指定 effort")
        for effort in ("low", "xhigh"):
            r = direct(SUMMARIZE_PROMPT, effort)
            rows.append(r)
            print(f"  {r['kind']:<22} effort={r['effort']:<6} output_tokens={r['output_tokens']}  （回答 {r['chars']} 字元）")
    except claude_cli_client.APIError as e:
        print(f"錯誤：{e}", file=sys.stderr)
        sys.exit(1)
    print(f"\nclaude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
