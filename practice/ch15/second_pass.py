"""第 15 章練習 1：批次結果分流器＋第二輪補救。

只有「拒答」轉備援模型；429、過載、逾時以指數退避重試同一個模型；其他未知錯誤交給人。
"""
import json
import sys
from pathlib import Path

CH15 = Path(__file__).resolve().parent
PRACTICE = CH15.parent
sys.path.insert(0, str(PRACTICE))

FALLBACK_MODEL = "claude-opus-4-8"
TRANSIENT_ERRORS = {"rate_limit_error", "overloaded_error", "timeout_error", "api_error"}
TRANSIENT_STATUS = {429, 500, 502, 503, 504, 529}
BACKOFF_BASE_S, MAX_RETRIES = 2, 3


def classify(result):
    """回傳 done／fallback／retry_same_model／manual。先看 result.type，再看 stop_reason 或錯誤種類。"""
    if not isinstance(result, dict):
        return "manual"
    kind = result.get("type")
    if kind == "succeeded":
        stop = (result.get("message") or {}).get("stop_reason")
        if stop == "refusal":
            return "fallback"  # 只有拒答走備援：換模型才有機會得到答案
        return "done" if stop in ("end_turn", "stop_sequence", "max_tokens", "tool_use") else "manual"
    if kind == "errored":
        error = result.get("error") or {}
        if error.get("type") in TRANSIENT_ERRORS or error.get("status") in TRANSIENT_STATUS:
            return "retry_same_model"  # 暫時性錯誤：模型沒有拒絕，只是現在沒空，換模型解決不了問題
        return "manual"  # invalid_request_error、authentication_error 等，重試也不會好
    if kind == "expired":
        return "retry_same_model"  # 批次在期限內沒處理到，不是內容問題
    return "manual"  # canceled 或看不懂的型態


def backoff_plan(result):
    """第 1/2/3 次重試要等幾秒：以 max(retry_after, 2 秒) 為基準每次加倍（實作時再加隨機抖動）。
    有 retry_after（429 常見）就從它開始倍增，否則是 2、4、8 秒。"""
    retry_after = (result.get("error") or {}).get("retry_after_s") or 0
    base = max(BACKOFF_BASE_S, retry_after)
    return [base * 2 ** (n - 1) for n in range(1, MAX_RETRIES + 1)]


def run_fallback(item):
    """以備援模型送出原本的提示詞（只換 model，其他欄位照舊）。"""
    import claude_cli_client
    req = dict(item["request"], model=FALLBACK_MODEL)
    msg = claude_cli_client.Anthropic().messages.create(**req)
    refused = msg.stop_reason == "refusal"
    return {
        "custom_id": item["custom_id"],
        "original_model": item["request"]["model"],
        "original_refusal_category": item["result"]["message"]["stop_details"]["category"],
        "served_by": msg.model,
        "stop_reason": msg.stop_reason,
        "output_tokens": msg.usage.output_tokens,
        "text": "" if refused or not msg.content else msg.content[0].text,
    }


def main():
    items = [json.loads(line) for line in (CH15 / "batch_results.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]
    routes = {it["custom_id"]: classify(it["result"]) for it in items}

    expected = {"ticket-001": "done", "ticket-002": "done", "sec-003": "fallback", "ticket-004": "retry_same_model",
                "ticket-005": "done", "sec-006": "fallback", "ticket-007": "retry_same_model",
                "ticket-008": "retry_same_model"}
    assert routes == expected, routes
    assert classify({"type": "errored", "error": {"type": "invalid_request_error", "status": 400}}) == "manual"
    assert classify({"type": "expired"}) == "retry_same_model" and classify({"type": "canceled"}) == "manual"
    assert classify(None) == "manual"
    assert backoff_plan({"type": "errored", "error": {"retry_after_s": 10}}) == [10, 20, 40]
    assert backoff_plan({"type": "errored", "error": {}}) == [2, 4, 8]
    print("分類 assert 全部通過（8 筆＋400／expired／canceled／None 邊界）\n")

    for it in items:
        r = it["result"]
        detail = (r.get("message") or {}).get("stop_details") or r.get("error") or {}
        print(f"  {it['custom_id']:<11} {routes[it['custom_id']]:<17} {r['type']:<10} "
              f"{detail.get('category') or detail.get('type') or ''}")

    print("\n== retry_same_model：只印計畫，不送出 ==")
    for it in items:
        if routes[it["custom_id"]] == "retry_same_model":
            waits = backoff_plan(it["result"])
            print(f"  {it['custom_id']}：會以指數退避重試 {it['request']['model']}，"
                  + "、".join(f"第 {n} 次等待 {w} 秒" for n, w in enumerate(waits, 1)))

    print(f"\n== fallback：以 {FALLBACK_MODEL} 真的送出原本的提示詞 ==")
    import claude_cli_client
    claude_cli_client.install()
    out_rows = []
    for it in items:
        if routes[it["custom_id"]] != "fallback":
            continue
        try:
            row = run_fallback(it)
        except claude_cli_client.APIError as e:
            row = {"custom_id": it["custom_id"], "served_by": None, "error": str(e)}
        out_rows.append(row)
        print(f"  {row['custom_id']}（原拒答類別 {row.get('original_refusal_category')}）→ served_by={row.get('served_by')} "
              f"stop_reason={row.get('stop_reason')} output_tokens={row.get('output_tokens')}")
        print("    " + (row.get("text") or row.get("error", "")).replace("\n", "\n    "))
    (CH15 / "second_pass_out.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in out_rows), encoding="utf-8")
    print(f"\n寫入 second_pass_out.jsonl：{len(out_rows)} 筆；claude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
