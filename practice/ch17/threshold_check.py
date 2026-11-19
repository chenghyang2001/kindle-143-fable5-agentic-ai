"""第 17 章練習 1：模擬 100 個提示詞的基準（4 個拒答）與這次結果（11 個拒答），檢查 canary 的漂移門檻。不呼叫模型。"""
import statistics

N, BASE_REFUSED, CUR_REFUSED = 100, 4, 11


def simulate(n_refused, n=N, ms=3000.0, score=1.0):
    """前 n_refused 個提示詞拒答，其餘正常；延遲與分數固定，只讓拒答率變化。"""
    results = [{"id": f"p{i:03d}", "refused": i < n_refused, "ms": ms, "score": 0.0 if i < n_refused else score}
               for i in range(n)]
    outcomes = {r["id"]: {"refused": r["refused"], "ms": r["ms"], "score": r["score"]} for r in results}
    return results, outcomes


def drift_alerts(results, outcomes, refusal_max=0.2, latency_max=1.5):
    # ---- 以下比較邏輯複製自 fable5/fable_scanner/canary.py run_canary() 第 108～120 行（未修改） ----
    refusal_rate = sum(r["refused"] for r in results) / len(results)
    base_refusal_rate = sum(o["refused"] for o in outcomes.values()) / max(1, len(outcomes))
    median_ms = statistics.median(r["ms"] for r in results)
    base_median_ms = statistics.median(o["ms"] for o in outcomes.values())
    mean_score = statistics.mean(r["score"] for r in results)

    alerts = []
    if refusal_rate - base_refusal_rate > refusal_max:
        alerts.append(f"refusal rate {refusal_rate:.0%} vs baseline {base_refusal_rate:.0%}")
    if base_median_ms and median_ms / base_median_ms > latency_max:
        alerts.append(f"median latency {median_ms:.0f}ms vs baseline {base_median_ms:.0f}ms")
    if mean_score < 0.6:
        alerts.append(f"mean expected-output score {mean_score:.0%} -- outputs diverging from baseline shape")
    # ---- 複製結束 ----
    return alerts, refusal_rate, base_refusal_rate, mean_score


def largest_catching_max(results, outcomes, step=0.001):
    """在 0～0.2 之間，以 step 為間隔，找出還能讓拒答率告警觸發的最大 refusal_max。"""
    best = None
    for k in range(int(0.2 / step) + 1):
        m = round(k * step, 6)
        if any(a.startswith("refusal rate") for a in drift_alerts(results, outcomes, refusal_max=m)[0]):
            best = m
    return best


def main():
    _, base_outcomes = simulate(BASE_REFUSED)
    cur_results, _ = simulate(CUR_REFUSED)
    alerts, rate, base_rate, mean_score = drift_alerts(cur_results, base_outcomes)
    diff = rate - base_rate
    print(f"基準：{N} 個提示詞、{BASE_REFUSED} 個拒答（{base_rate:.0%}）；這次：{CUR_REFUSED} 個拒答（{rate:.0%}）")
    print(f"拒答率差 = {rate} − {base_rate} = {diff!r}（{diff:.2%}，{rate / base_rate:.2f} 倍）")
    print(f"平均分數 = {mean_score:.2%}（拒答算 0 分）")
    print(f"\n預設 refusal_max=0.2：{'告警 ' + str(alerts) if alerts else '不告警'}（條件是差 > 0.2，{diff:.2f} 遠小於 0.2）")

    best = largest_catching_max(cur_results, base_outcomes)
    print(f"\n以 0.001 為間隔掃描：最大能抓到這次漂移的 refusal_max = {best}")
    for m in (0.05, best, 0.07, 0.1):
        hit = any(a.startswith("refusal rate") for a in drift_alerts(cur_results, base_outcomes, refusal_max=m)[0])
        print(f"  refusal_max={m:<6} → {'告警' if hit else '不告警'}")
    print("  （條件是嚴格大於：差剛好 0.07，所以 refusal_max=0.07 不會告警，要嚴格小於 0.07 才抓得到）")

    # 預設門檻要到多少拒答才會告警
    need = next(k for k in range(N + 1)
                if any(a.startswith("refusal rate") for a in drift_alerts(simulate(k)[0], base_outcomes)[0]))
    print(f"\n預設 0.2 下，基準 4% 時要到 {need} 個拒答（{need}%）才會告警，是基準的 {need / BASE_REFUSED:.1f} 倍")

    assert not alerts, "預設門檻應該不告警"
    assert best is not None and 0.069 <= best < 0.071
    print("\nassert 通過")


if __name__ == "__main__":
    main()
