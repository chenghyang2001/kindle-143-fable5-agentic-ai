"""第 12 章練習 1：提示快取損益計算器＋前綴排序檢查器（只用標準庫，不呼叫模型）。"""
import math

# ---- 倍率與單價（每個數字都註明出處）----
WRITE_MULT = {
    "5m": 1.25,  # 書中第 12 章：5 分鐘快取寫入 1.25 倍（題目也給定）
    "1h": 2.0,   # 書中第 12 章：1 小時快取寫入 2 倍（題目也給定）
}
READ_MULT = 0.1        # 假設，需查官方定價頁確認：讀取快取＝輸入單價 × 0.1
BATCH_DISCOUNT = 0.5   # 假設，需查官方定價頁確認：批次 API 打 5 折
FABLE_INPUT_PER_M = 10.0  # fable5/README.md 第 121 行：Fable 5 $10／$50 per million（取輸入價）
TTL_RANK = {"1h": 2, "5m": 1, None: 0}  # 存活期越長，越應該放在前面

BOOK_BREAK_EVEN = {"5m": 1, "1h": 2}  # 書中說法：5 分鐘複用 1 次就回本，1 小時要 2 次才打平


def cost(n_calls, prefix_tokens, ttl, price_per_m, writes=1, batch=False):
    """回傳 (不用快取的總輸入成本, 用快取的總輸入成本)，只算共用前綴那一段。

    writes：這段期間快取寫入幾次（快取過期就要重寫）；其餘呼叫都算讀取。
    ttl=None 代表不快取，兩個數字相同。batch=True 時兩者都套批次折扣。
    """
    if n_calls < 0 or prefix_tokens < 0 or price_per_m < 0:
        raise ValueError("n_calls、prefix_tokens、price_per_m 不可為負")
    if ttl not in TTL_RANK:
        raise ValueError(f"未知的 ttl：{ttl!r}")
    unit = prefix_tokens / 1_000_000 * price_per_m * (BATCH_DISCOUNT if batch else 1.0)
    no_cache = n_calls * unit
    if ttl is None or n_calls == 0:
        return no_cache, no_cache
    writes = min(max(writes, 1), n_calls)
    cached = writes * WRITE_MULT[ttl] * unit + (n_calls - writes) * READ_MULT * unit
    return no_cache, cached


def break_even(ttl):
    """最少要「複用」幾次（第一次寫入之後再讀幾次），快取總成本才 ≤ 不快取。"""
    w = WRITE_MULT[ttl]
    # 寫一次＋讀 k 次：w + 0.1k ≤ 1 + k  →  k ≥ (w − 1) / (1 − 0.1)
    return max(0, math.ceil((w - 1) / (1 - READ_MULT) - 1e-12))


def check_order(blocks):
    """依序檢查前綴區塊。存活期較短（或不快取）的區塊排在較長存活期的區塊前面，就回報問題。

    前綴快取是「從頭比對」：前面任何一塊變了或過期，它後面所有已快取的區塊都要重寫。
    回傳 [{"block": 排錯的區塊, "index": 位置, "invalidates": [會跟著失效的區塊名稱]}]，空清單代表排序正確。
    """
    problems = []
    for i, blk in enumerate(blocks):
        rank = TTL_RANK.get(blk.get("ttl"), 0)
        later = blocks[i + 1:]
        if any(TTL_RANK.get(b.get("ttl"), 0) > rank for b in later):
            problems.append({
                "block": blk["name"], "index": i, "ttl": blk.get("ttl"),
                "invalidates": [b["name"] for b in later if b.get("ttl") is not None],
            })
    return problems


def _fmt(problems):
    if not problems:
        return "排序正確"
    return "；".join(f"第 {p['index'] + 1} 塊「{p['block']}」（ttl={p['ttl']}）排錯，"
                    f"它一變就讓 {p['invalidates']} 快取失效" for p in problems)


def main():
    print("== 1. 倍率與單價 ==")
    print(f"寫入 5m×{WRITE_MULT['5m']}、1h×{WRITE_MULT['1h']}（書中）；讀取×{READ_MULT}、批次×{BATCH_DISCOUNT}"
          "（假設，需查官方定價頁確認）；Fable 輸入 ${}/M（README）\n".format(FABLE_INPUT_PER_M))

    print("== 2. 回本次數 ==")
    for ttl in ("5m", "1h"):
        k = break_even(ttl)
        w = WRITE_MULT[ttl]
        lose = w + READ_MULT * (k - 1) - k  # 少複用一次時快取多付的倍數
        verdict = "一致" if k == BOOK_BREAK_EVEN[ttl] else f"不一致（書中 {BOOK_BREAK_EVEN[ttl]} 次）"
        print(f"{ttl}：k ≥ ({w} − 1) / (1 − {READ_MULT}) = {(w - 1) / (1 - READ_MULT):.3f} → 最少複用 {k} 次；"
              f"快取 {w + READ_MULT * k:.2f} 倍 vs 不快取 {1 + k} 倍；"
              f"只複用 {k - 1} 次時快取多付 {lose:+.2f} 倍 → 與書中說法{verdict}")

    print("\n== 3. 每日成本：80,000 token 共用前綴 × 200 次／天，Fable 輸入 $10/M ==")
    n, prefix = 200, 80_000
    base, _ = cost(n, prefix, None, FABLE_INPUT_PER_M)
    scenarios = [
        ("無快取", cost(n, prefix, None, FABLE_INPUT_PER_M)[1]),
        ("5 分鐘快取（假設每 5 分鐘內都有呼叫 → 一天只寫 1 次）", cost(n, prefix, "5m", FABLE_INPUT_PER_M)[1]),
        ("1 小時快取（一天只寫 1 次）", cost(n, prefix, "1h", FABLE_INPUT_PER_M)[1]),
        ("1 小時快取＋批次折扣", cost(n, prefix, "1h", FABLE_INPUT_PER_M, batch=True)[1]),
    ]
    for name, c in scenarios:
        print(f"  {name:<44} ${c:>8.2f}／天  降幅 {(1 - c / base):6.1%}")
    print("  敏感度（假設不成立時）：200 次平均分散在 24 小時 → 每 7.2 分鐘一次，比 5 分鐘還久")
    c5 = cost(n, prefix, "5m", FABLE_INPUT_PER_M, writes=n)[1]
    c1 = cost(n, prefix, "1h", FABLE_INPUT_PER_M, writes=1)[1]
    print(f"  {'5 分鐘快取：每次都過期、每次都重寫':<44} ${c5:>8.2f}／天  降幅 {(1 - c5 / base):6.1%}")
    print(f"  {'1 小時快取：每次讀取都續命、仍只寫 1 次':<44} ${c1:>8.2f}／天  降幅 {(1 - c1 / base):6.1%}")

    print("\n== 4. 前綴排序檢查 ==")
    good = [{"name": "工具定義", "ttl": "1h"}, {"name": "系統提示詞", "ttl": "1h"},
            {"name": "本章教材", "ttl": "5m"}, {"name": "這次的提問", "ttl": None}]
    bad = [{"name": "今天日期與時間", "ttl": None}, {"name": "工具定義", "ttl": "1h"},
           {"name": "系統提示詞", "ttl": "1h"}, {"name": "本章教材", "ttl": "5m"}]
    print(f"  正確排序：{_fmt(check_order(good))}")
    print(f"  倒置排序：{_fmt(check_order(bad))}")

    # ---- 檢查 ----
    assert break_even("5m") == 1 and break_even("1h") == 2, "回本次數應與書中一致"
    assert check_order(good) == []
    bad_result = check_order(bad)
    assert len(bad_result) == 1 and bad_result[0]["block"] == "今天日期與時間"
    assert bad_result[0]["invalidates"] == ["工具定義", "系統提示詞", "本章教材"]
    assert check_order([]) == []
    mixed = check_order([{"name": "A", "ttl": "5m"}, {"name": "B", "ttl": "1h"}])
    assert [p["block"] for p in mixed] == ["A"] and mixed[0]["invalidates"] == ["B"]
    assert cost(0, prefix, "1h", FABLE_INPUT_PER_M) == (0, 0)
    assert abs(base - 160.0) < 1e-9
    try:
        cost(1, prefix, "2h", FABLE_INPUT_PER_M)
        raise AssertionError("未知 ttl 應該拋 ValueError")
    except ValueError:
        pass
    print("\n全部 assert 通過（回本次數 2、正確排序、倒置排序、空清單、5m 在 1h 前、0 次呼叫、基準 $160、未知 ttl）")


if __name__ == "__main__":
    main()
