"""第 6 章練習 2：證明 sample_target.parse_log 會默默少算格式壞掉的行。"""
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE / "fable5" / "projects" / "04_refactor_legacy"))
import sample_target as st  # noqa: E402  只讀不改

LOG = Path(__file__).with_name("sample.log")


def main() -> None:
    try:
        lines = LOG.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        print(f"錯誤：讀不到 {LOG}：{e}", file=sys.stderr)
        sys.exit(1)
    events = st.parse_log(LOG)
    print(f"sample.log 總行數：{len(lines)}")
    print(f"parse_log 回傳事件數：{len(events)}")
    print(f"少算：{len(lines) - len(events)} 行，沒有任何例外、警告或回傳值說明\n")
    print("逐行檢查 parse_line：")
    for n, line in enumerate(lines, 1):
        result = st.parse_line(line)
        mark = "OK  " if result else "DROP"
        print(f"  第 {n:>2} 行 {mark} {line}")
    print()
    print(r"被丟掉的行與原因（對照 PATTERN = ^(\S+) (\S+) severity=(\d) user=(\S+) (.*)$）：")
    reasons = {
        4: r"severity=10 是兩位數，(\d) 只吃一位數",
        6: "少了 user= 欄位",
        8: r"user= 後面是空的，(\S+) 至少要一個非空白字元",
    }
    for n, why in reasons.items():
        assert st.parse_line(lines[n - 1]) is None, f"第 {n} 行預期被丟掉"
        print(f"  第 {n} 行：{why}")
    dropped_sev = [int(l.split("severity=")[1].split()[0]) for i, l in enumerate(lines, 1) if i in reasons]
    print(f"\n被丟掉的 3 行 severity 分別是 {dropped_sev}，最高的兩筆（10、9）都在裡面")


if __name__ == "__main__":
    main()
