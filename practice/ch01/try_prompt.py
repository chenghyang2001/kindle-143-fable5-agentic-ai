"""第 1 章練習 1：同一個任務，分別用舊版與 Harness 式系統提示詞各送一次（共 2 次 claude -p）。"""
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()

CH01 = PRACTICE / "ch01"
TASK = "CI 的 build 失敗了，錯誤是 ModuleNotFoundError: No module named 'yaml'，請處理。"
RUNS = [
    ("舊版 bad_prompt.md", PRACTICE / "fable5" / "fable_scanner" / "examples" / "bad_prompt.md", CH01 / "answer-old.md"),
    ("新版 system_prompt.md", CH01 / "system_prompt.md", CH01 / "answer-new.md"),
]


def ask(system_text: str) -> str:
    """送一次請求，回傳文字；拒答或空回應時拋錯，避免把空檔當成答案。"""
    client = claude_cli_client.Anthropic()
    resp = client.messages.create(
        model="claude-fable-5",
        max_tokens=4000,
        system=system_text,
        messages=[{"role": "user", "content": TASK}],
    )
    if resp.stop_reason == "refusal":
        raise RuntimeError("模型拒答")
    if not resp.content or not resp.content[0].text.strip():
        raise RuntimeError(f"空回應（stop_reason={resp.stop_reason}）")
    return resp.content[0].text


def main() -> None:
    for label, system_path, out_path in RUNS:
        try:
            system_text = system_path.read_text(encoding="utf-8")
            answer = ask(system_text)
        except (OSError, RuntimeError) as e:
            print(f"錯誤（{label}）：{e}", file=sys.stderr)
            sys.exit(1)
        header = f"# 回答：{label}\n\n- 任務：{TASK}\n- model：claude-fable-5（經 claude -p 轉接層）\n\n---\n\n"
        out_path.write_text(header + answer + "\n", encoding="utf-8")
        print(f"已寫入 {out_path.name}（{len(answer)} 字元）")
    print(f"呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
