"""第 7 章練習 2：影子比對。兩個日常提示詞 × 兩個模型（Opus 4.8／Fable 5），effort medium，共 4 次 claude -p。

不比字面，比「性質」：每個提示詞定義 2～3 個可檢查的性質，兩個模型各跑一次。
"""
import re
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()

OUT = Path(__file__).with_name("shadow-results.md")
MODELS = ["claude-opus-4-8", "claude-fable-5"]
ALLOWED_LABELS = {"bug", "config", "network"}

# 包一層 _run_cli：不增加呼叫，只記下 CLI 回報實際用了哪個模型（modelUsage），
# 因為轉接層回傳的 msg.model 只是照抄請求的 model。
_served = []
_orig_run_cli = claude_cli_client._run_cli


def _run_cli_recording(*args, **kwargs):
    data = _orig_run_cli(*args, **kwargs)
    _served.append(sorted((data.get("modelUsage") or {}).keys()))
    return data


claude_cli_client._run_cli = _run_cli_recording


def bullet_lines(text):
    return [ln for ln in text.strip().splitlines() if ln.strip()]


TASKS = [
    {
        "name": "錯誤分類",
        "prompt": ("把這段錯誤訊息分類成 bug／config／network，只回一個詞。\n\n"
                   "錯誤訊息：requests.exceptions.ConnectTimeout: HTTPSConnectionPool(host='api.internal', "
                   "port=443): Max retries exceeded (Caused by ConnectTimeoutError: timed out after 10s)"),
        "checks": [
            ("只有一個詞", lambda t: len(t.strip().split()) == 1),
            ("在允許清單內", lambda t: t.strip().strip(".").lower() in ALLOWED_LABELS),
            ("答對 network", lambda t: t.strip().strip(".").lower() == "network"),
        ],
    },
    {
        "name": "部署紀錄摘要",
        "prompt": ("用三點條列總結這段部署紀錄，每點一行，不要前言或結語。\n\n"
                   "10:02 開始部署 checkout-service v2.14.0 到 prod（3 個 pod）\n"
                   "10:04 pod-1、pod-2 健康檢查通過\n"
                   "10:06 pod-3 健康檢查失敗：DB_POOL_SIZE 未設定，CrashLoopBackOff\n"
                   "10:09 補上 DB_POOL_SIZE=20 後重啟 pod-3，健康檢查通過\n"
                   "10:11 錯誤率 0.2%，與部署前相同；部署完成"),
        "checks": [
            ("恰好三行", lambda t: len(bullet_lines(t)) == 3),
            ("每行都是條列符號開頭", lambda t: all(re.match(r"^\s*(?:[-*•]|\d+[.)])\s+", ln) for ln in bullet_lines(t))),
            ("總長 ≤ 300 字元", lambda t: len(t.strip()) <= 300),
        ],
    },
]


def run_one(task, model):
    resp = claude_cli_client.Anthropic().messages.create(
        model=model, max_tokens=300, output_config={"effort": "medium"},
        messages=[{"role": "user", "content": task["prompt"]}],
    )
    if resp.stop_reason == "refusal" or not resp.content:
        return {"text": "", "tokens": resp.usage.output_tokens, "results": [(n, False) for n, _ in task["checks"]],
                "note": f"stop_reason={resp.stop_reason}"}
    text = resp.content[0].text
    return {"text": text, "tokens": resp.usage.output_tokens,
            "results": [(n, bool(fn(text))) for n, fn in task["checks"]], "note": ""}


def cell(text):
    return text.strip().replace("|", "\\|").replace("\n", " ⏎ ")[:80]


def main():
    rows, details = [], []
    for task in TASKS:
        for model in MODELS:
            try:
                r = run_one(task, model)
            except claude_cli_client.APIError as e:  # 轉接層的錯誤都繼承 APIError
                print(f"錯誤（{task['name']}／{model}）：{e}", file=sys.stderr)
                sys.exit(1)
            served = ", ".join(_served[-1]) or "（CLI 沒回報）"
            passed = sum(ok for _, ok in r["results"])
            rows.append(f"| {task['name']} | {model} | {served} | {passed}/{len(r['results'])} | {r['tokens']} | {cell(r['text'])} |")
            marks = "；".join(f"{n} {'✅' if ok else '❌'}" for n, ok in r["results"])
            details.append(f"### {task['name']}／{model}\n\n- 性質：{marks}\n- output_tokens：{r['tokens']}\n"
                           f"- 原文：\n\n```text\n{r['text'].strip()}\n```\n")
            print(f"{task['name']:<8} {model:<16} served={served:<20} {passed}/{len(r['results'])}  tokens={r['tokens']}")
    OUT.write_text("# 影子比對結果\n\n<!-- RESULTS -->\n"
                   "| 提示詞 | 請求模型 | CLI 回報實際模型 | 性質通過數 | output_tokens | 原文前 80 字 |\n"
                   "| --- | --- | --- | --- | --- | --- |\n" + "\n".join(rows) + "\n\n## 逐筆明細\n\n"
                   + "\n".join(details), encoding="utf-8")
    print(f"claude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
