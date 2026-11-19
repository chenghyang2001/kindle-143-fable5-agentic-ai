"""不改 fable5 原始碼，讓範例透過 claude -p 轉接層執行。

用法（在 practice/ 底下）：
    PYTHONUTF8=1 python run_with_cli.py fable5/projects/03_cost_dashboard/cost_dashboard.py
    PYTHONUTF8=1 python run_with_cli.py -m fable_scanner canary run
    K143_CLI_MODEL=haiku PYTHONUTF8=1 python run_with_cli.py fable5/agentic_soc/triage_loop.py fable5/agentic_soc/sample_alerts.jsonl

做法：先 install() 把 claude_cli_client 註冊成 `anthropic` 模組，
再用 runpy 以 __main__ 身分執行目標腳本或模組，sys.argv 照常傳下去。
"""
import runpy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import claude_cli_client

USAGE = "用法：python run_with_cli.py <腳本.py | -m 模組> [參數…]"


def main(argv):
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    claude_cli_client.install()
    try:
        if argv[0] == "-m":
            if len(argv) < 2:
                print(USAGE, file=sys.stderr)
                return 2
            sys.argv = [argv[1]] + argv[2:]
            runpy.run_module(argv[1], run_name="__main__", alter_sys=True)
        else:
            script = Path(argv[0])
            if not script.is_file():
                print(f"錯誤：找不到腳本 {script}", file=sys.stderr)
                return 2
            sys.argv = [str(script)] + argv[1:]
            sys.path.insert(0, str(script.resolve().parent))
            runpy.run_path(str(script), run_name="__main__")
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else (0 if code is None else 1)
    except claude_cli_client.APIError as exc:
        print(f"[run_with_cli] 轉接層錯誤：{exc}", file=sys.stderr)
        return 1
    finally:
        sys.stdout.flush()  # 讓呼叫次數印在範例輸出之後
        print(f"[run_with_cli] 本次共呼叫 claude -p {claude_cli_client.calls_made()} 次", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
