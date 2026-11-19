"""第 3 章練習 2：用轉接層對 ch03/mem 跑開機檢疫（4 個檔 × 1 次 low effort ＝ 4 次 claude -p）。"""
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()
import memory.startup_scan as ss  # noqa: E402

MEM = PRACTICE / "ch03" / "mem"


def main() -> None:
    if not (MEM / "lessons").is_dir():
        print(f"錯誤：找不到 {MEM / 'lessons'}", file=sys.stderr)
        sys.exit(1)
    ss.scan(MEM)  # 隔離區是 ch03/mem/_quarantine，不碰 fable5/
    print(f"claude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
