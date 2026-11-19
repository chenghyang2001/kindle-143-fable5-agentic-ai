"""第 2 章練習 1：用轉接層跑 SOC 分流迴圈，只處理前 2 筆告警（2 ×（分類＋驗證）＝ 4 次 claude -p）。"""
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()  # 必須在 import 範例之前，模組層的 client = Anthropic() 才會拿到轉接層
import agentic_soc.triage_loop as tl  # noqa: E402

CH02 = PRACTICE / "ch02"
SOURCE = PRACTICE / "fable5" / "agentic_soc" / "sample_alerts.jsonl"
QUEUE = CH02 / "two_alerts.jsonl"

# 執行期寫入的 lessons 改到 ch02/，不碰 fable5/
tl.LESSONS = CH02 / "lessons"


def main() -> None:
    try:
        first_two = SOURCE.read_text(encoding="utf-8").splitlines()[:2]
    except OSError as e:
        print(f"錯誤：讀不到 {SOURCE}：{e}", file=sys.stderr)
        sys.exit(1)
    QUEUE.write_text("\n".join(first_two) + "\n", encoding="utf-8")
    sys.argv = [sys.argv[0], str(QUEUE)]
    tl.main()
    print(f"claude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
