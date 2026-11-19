"""第 11 章練習 1：跨模型重放輔助函式 prepare_history()。

規則：
- 同一個模型重放：歷史必須逐位元組原封不動（連空的 thinking、redacted_thinking 都要保留）。
- 換模型重放：移除 assistant 回合裡的 thinking／redacted_thinking，其他不動。
"""
import copy
import json
import sys
from pathlib import Path

THINKING_TYPES = ("thinking", "redacted_thinking")
# 某則 assistant 訊息只剩思考區塊時，移除後補上的說明文字
PLACEHOLDER_TEXT = "（此回合原本只有思考內容，已在切換模型時移除）"


def _dumps(obj):
    return json.dumps(obj, ensure_ascii=False)


def prepare_history(messages, source_model, target_model):
    """回傳可以送給 target_model 的歷史（深拷貝，不修改傳入的物件）。"""
    if not isinstance(messages, list):
        raise TypeError(f"messages 必須是 list，拿到 {type(messages).__name__}")
    history = copy.deepcopy(messages)
    if source_model == target_model:
        # 同模型：思考區塊帶有簽章，伺服器會驗證它和產生它的模型、上下文是否吻合；
        # 任何「整理」（連刪掉空的 thinking）都可能讓驗證失敗或讓快取對不上，所以一個位元組都不動。
        return history

    for msg in history:
        if msg.get("role") != "assistant" or not isinstance(msg.get("content"), list):
            continue  # user 訊息、字串形式的 content 都不會帶思考區塊
        kept = [b for b in msg["content"] if not (isinstance(b, dict) and b.get("type") in THINKING_TYPES)]
        if not kept:
            # 不能整則刪掉：那會讓兩個 user 訊息相鄰，破壞 user／assistant 交替的結構；
            # 也不能留空陣列：API 不接受 content 為空的 assistant 訊息。
            # 所以留一個說明性的 text 區塊，讓對話結構完整，也讓讀紀錄的人知道這裡少了什麼。
            kept = [{"type": "text", "text": PLACEHOLDER_TEXT}]
        msg["content"] = kept
    return history


def well_meaning_cleanup(messages, source_model, target_model):
    """錯誤示範：「好心」在同模型時也把空的 thinking 區塊清掉，看起來比較乾淨。"""
    history = prepare_history(messages, source_model, target_model)
    if source_model == target_model:
        for msg in history:
            if msg.get("role") == "assistant" and isinstance(msg.get("content"), list):
                msg["content"] = [b for b in msg["content"]
                                  if not (b.get("type") == "thinking" and b.get("thinking") == "")]
    return history


def count_types(messages):
    counts = {}
    for msg in messages:
        if isinstance(msg.get("content"), list):
            for b in msg["content"]:
                counts[b.get("type")] = counts.get(b.get("type"), 0) + 1
    return counts


def lint_both(original, prepared, target_model):
    """把處理前、處理後各包成請求本體，用 migration_linter.lint() 各跑一次。"""
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "fable5"))
    from migration.migration_linter import lint
    wrap = lambda msgs: {"model": target_model, "max_tokens": 1024,  # noqa: E731
                         "output_config": {"effort": "high"},
                         "fallbacks": [{"model": "claude-opus-4-8"}], "messages": msgs}
    return lint(wrap(original)), lint(wrap(prepared))


if __name__ == "__main__":
    FABLE, OPUS = "claude-fable-5", "claude-opus-4-8"
    path = Path(__file__).with_name("history.json")
    try:
        original = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"錯誤：讀不到 {path}：{e}", file=sys.stderr)
        sys.exit(1)
    snapshot = _dumps(original)
    print(f"history.json：{len(original)} 則訊息，區塊類型 {count_types(original)}\n")

    # 1. 同模型：逐位元組相同（含空 thinking 與 redacted_thinking）
    same = prepare_history(original, FABLE, FABLE)
    assert _dumps(same) == snapshot
    assert same is not original and same[1] is not original[1], "必須是深拷貝"
    print("ok  1 同模型（fable → fable）：json.dumps 逐位元組相同，且是深拷貝")

    # 2. 跨模型：沒有任何思考區塊
    cross = prepare_history(original, FABLE, OPUS)
    assert not any(t in count_types(cross) for t in THINKING_TYPES)
    print(f"ok  2 跨模型（fable → opus）：思考區塊歸零，區塊類型 {count_types(cross)}")

    # 3. 原物件沒有被改（兩次呼叫之後）
    assert _dumps(original) == snapshot
    print("ok  3 兩次呼叫後原物件仍與讀入時逐位元組相同")

    # 4. tool_use／tool_result 原樣保留（含 id 對應）
    tu = [b for m in cross if isinstance(m["content"], list) for b in m["content"] if b["type"] == "tool_use"]
    tr = [b for m in cross if isinstance(m["content"], list) for b in m["content"] if b["type"] == "tool_result"]
    assert tu == [original[1]["content"][2]] and tr == [original[2]["content"][0]]
    assert tu[0]["id"] == tr[0]["tool_use_id"] == "toolu_01"
    print("ok  4 tool_use 與 tool_result 原樣保留，toolu_01 仍然對得上")

    # 5. 只有 redacted_thinking 的那則 assistant 變成說明 text，訊息數與交替結構不變
    assert cross[5] == {"role": "assistant", "content": [{"type": "text", "text": PLACEHOLDER_TEXT}]}
    assert len(cross) == len(original)
    assert [m["role"] for m in cross] == [m["role"] for m in original]
    print(f"ok  5 第 6 則（原本只有 redacted_thinking）→ 說明 text；訊息數 {len(cross)}，user／assistant 交替不變")

    # 6. 其餘內容不動：text 區塊逐字相同、第 4 則只少了空 thinking
    assert cross[3]["content"] == [original[3]["content"][1]]
    assert cross[7] == original[7] and cross[0] == original[0]
    print("ok  6 非思考區塊逐字相同（第 4 則只移除空 thinking，第 8 則完全不變）")

    # 7. 邊界：空歷史、非 list
    assert prepare_history([], FABLE, OPUS) == []
    try:
        prepare_history("not a list", FABLE, OPUS)
        raise AssertionError("應該拋 TypeError")
    except TypeError:
        pass
    print("ok  7 邊界：空歷史回空 list；非 list 拋 TypeError")

    # 錯誤示範：好心清洗破壞同模型規則
    bad = well_meaning_cleanup(original, FABLE, FABLE)
    assert _dumps(bad) != snapshot
    print(f"\n錯誤示範 well_meaning_cleanup(fable → fable)：逐位元組相同？{_dumps(bad) == snapshot}"
          f"（thinking 區塊 {count_types(original).get('thinking')} → {count_types(bad).get('thinking')}，"
          f"長度 {len(snapshot)} → {len(_dumps(bad))} 字元）")

    # linter 前後對照
    before, after = lint_both(original, cross, OPUS)
    print(f"\nmigration_linter.lint()，model={OPUS}：")
    print(f"  處理前：{[(f, s) for f, s, _ in before] or 'clean'}")
    print(f"  處理後：{[(f, s) for f, s, _ in after] or 'clean'}")
    assert any(f == "messages" for f, _, _ in before) and not any(f == "messages" for f, _, _ in after)
    print("ok  8 處理前有 messages 警告，處理後消失")
    print("\n全部通過")
