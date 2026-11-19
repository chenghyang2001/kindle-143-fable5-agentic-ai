"""第 7 章練習 1：遷移 CI 閘門。掃描資料夾裡每份 JSON 請求本體，任何 error 就 exit 1。

用法：PYTHONUTF8=1 python ch07/ci_gate.py [資料夾，預設 ch07/requests]
"""
import json
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE / "fable5"))
from migration.migration_linter import lint  # noqa: E402

DEFAULT_DIR = Path(__file__).with_name("requests")


def check_file(path):
    """回傳 (errors, others)；讀不到或不是合法 JSON 也算 error，不能讓壞檔偷偷通過。"""
    try:
        req = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        return [("<file>", "error", f"無法讀取或解析：{e}")], []
    if not isinstance(req, dict):
        return [("<file>", "error", "請求本體必須是 JSON 物件")], []
    findings = lint(req)
    return [f for f in findings if f[1] == "error"], [f for f in findings if f[1] != "error"]


def main():
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DIR
    files = sorted(folder.glob("*.json"))
    if not files:
        print(f"錯誤：{folder} 底下沒有 .json 請求", file=sys.stderr)
        return 2
    failed = 0
    for path in files:
        errors, others = check_file(path)
        status = "FAIL" if errors else "PASS"
        print(f"[{status}] {path.name}")
        for field, sev, _ in errors + others:
            print(f"    {sev:<5} {field}")
        failed += bool(errors)
    print(f"\n{len(files)} 份請求，{failed} 份有 error（會在 Fable 5 回 400）")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
