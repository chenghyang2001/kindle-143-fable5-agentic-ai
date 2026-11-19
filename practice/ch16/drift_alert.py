"""第 16 章練習 1：用 fable_scanner.monitor.analyze() 做拒答比率漂移告警。

用法：PYTHONUTF8=1 python ch16/drift_alert.py <基準週 log[,log...]> <本週 log[,log...]>
"""
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE / "fable5"))
from fable_scanner.monitor import CATEGORIES, analyze  # noqa: E402

NAIVE_COUNT = 10        # 天真版：次數 > 10 就告警
RATIO_PP = 0.01         # 比率版：比上週高出 1 個百分點以上
RATIO_MULT = 2.0        # 或高出 2 倍以上（上週是 0 時視為無限倍）
SERIES = list(CATEGORIES) + ["fallback_served", "refused_total"]


def load(spec):
    lines = []
    for p in spec.split(","):
        try:
            lines += Path(p).read_text(encoding="utf-8").splitlines()
        except OSError as e:
            raise SystemExit(f"錯誤：讀不到 {p}：{e}")
    return analyze(lines)


def counts(stats):
    c = dict(stats["by_category"])
    c["fallback_served"] = stats["fallback_served"]
    c["refused_total"] = stats["refused"]
    return c


def rate(n, total):
    return n / total if total else 0.0


def naive_alerts(stats):
    return [f"{s} 次數 {n} > {NAIVE_COUNT}" for s, n in counts(stats).items() if n > NAIVE_COUNT]


def ratio_alerts(base, cur):
    alerts = []
    bc, cc = counts(base), counts(cur)
    for s in SERIES:
        rb, rc = rate(bc[s], base["total"]), rate(cc[s], cur["total"])
        if rc == 0:
            continue
        mult = rc / rb if rb else float("inf")
        if rc - rb >= RATIO_PP or mult >= RATIO_MULT:
            alerts.append(f"{s} 比率 {rb:.2%} → {rc:.2%}（+{(rc - rb) * 100:.2f} 個百分點，{mult:.1f} 倍）")
    return alerts


def table(name, stats):
    print(f"{name}：總請求 {stats['total']}")
    for s, n in counts(stats).items():
        print(f"  {s:<22} {n:>5} 次  {rate(n, stats['total']):6.2%}")


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    base, cur = load(argv[0]), load(argv[1])
    table(f"基準 {argv[0]}", base)
    table(f"本週 {argv[1]}", cur)
    for label, stats in (("基準", base), ("本週", cur)):
        a = naive_alerts(stats)
        print(f"\n(a) 天真版（次數 > {NAIVE_COUNT}）— {label}：" + ("；".join(a) if a else "無告警"))
    a = ratio_alerts(base, cur)
    print(f"\n(b) 比率版（+{RATIO_PP * 100:.0f} 個百分點以上或 {RATIO_MULT:.0f} 倍以上）：" + ("\n    " + "\n    ".join(a) if a else "無告警"))
    return 1 if a else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
