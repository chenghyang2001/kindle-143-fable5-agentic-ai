"""第 9 章練習 1：用假 client 驗證 credit 重試的「本體完全一致」（不呼叫任何模型）。"""
import copy
import sys
from pathlib import Path
from types import SimpleNamespace as NS

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "fable5"))
from fallback_credit import credit_retry as cr  # noqa: E402

FABLE, OPUS = "claude-fable-5", "claude-opus-4-8"
IGNORED_KEYS = ("model", "fallback_credit")


class FakeClient:
    """client.beta.messages.create(**kw)：記下每次的 kw，照劇本依序回傳。"""

    def __init__(self, script):
        self.calls = []
        self._script = list(script)
        self.beta = NS(messages=NS(create=self._create))

    def _create(self, **kw):
        self.calls.append(copy.deepcopy(kw))  # 深拷貝：之後有人改了 dict 也不影響紀錄
        if not self._script:
            raise AssertionError(f"劇本用完了，卻有第 {len(self.calls)} 次呼叫")
        return self._script.pop(0)


def ok(text, iters=("message",)):
    return NS(stop_reason="end_turn", stop_details=None, content=[NS(type="text", text=text)],
              usage=NS(iterations=[NS(type=t) for t in iters]))


def refusal(token=None, prefill=False):
    details = NS(category="cyber", fallback_has_prefill_claim=prefill)
    if token is not None:
        details.fallback_credit_token = token
    return NS(stop_reason="refusal", stop_details=details, content=[], usage=NS(iterations=[NS(type="message")]))


def params():
    """一份典型請求：長系統提示詞＋多回合訊息（含一個空字串的 text 區塊，模擬真實歷史紀錄）。"""
    return {
        "model": FABLE,
        "max_tokens": 2048,
        "output_config": {"effort": "high"},
        "system": [{"type": "text", "text": "你是 SOC 分析師。" * 50, "cache_control": {"type": "ephemeral"}}],
        "messages": [
            {"role": "user", "content": "分析這筆告警：A-1002 powershell -enc"},
            {"role": "assistant", "content": [{"type": "text", "text": ""}, {"type": "text", "text": "先看父程序。"}]},
            {"role": "user", "content": "父程序是 wmiprvse.exe，繼續。"},
        ],
    }


def body_matches(first, retry):
    """忽略 model 與 fallback_credit 後，兩個請求本體是否逐欄位完全相同（含順序）。"""
    strip = lambda req: {k: v for k, v in req.items() if k not in IGNORED_KEYS}  # noqa: E731
    return strip(first) == strip(retry)


def test_a_first_call_succeeds():
    client = FakeClient([ok("直接回答")])
    msg = cr.manual_fallback_with_credit(client, params(), OPUS)
    assert msg.content[0].text == "直接回答"
    assert len(client.calls) == 1
    assert client.calls[0]["model"] == FABLE and client.calls[0]["betas"] == [cr.CREDIT_BETA]
    assert "fallback_credit" not in client.calls[0]
    return "只呼叫 1 次，沒有帶 fallback_credit"


def test_b_refusal_with_token_retries_with_exact_body():
    original = params()
    client = FakeClient([refusal(token="tok-123", prefill=True), ok("備援回答")])
    msg = cr.manual_fallback_with_credit(client, original, OPUS)
    first, retry = client.calls
    assert msg.content[0].text == "備援回答" and len(client.calls) == 2
    assert first["model"] == FABLE and retry["model"] == OPUS
    assert retry["fallback_credit"] == {"token": "tok-123", "has_prefill_claim": True}
    assert body_matches(first, retry), "除了 model 與 fallback_credit 之外應該完全相同"
    assert list(k for k in first if k not in IGNORED_KEYS) == list(k for k in retry if k not in IGNORED_KEYS)
    assert original == params(), "呼叫端傳進來的 params 不應被修改"
    return "2 次呼叫；第二次只換了 model＋加了 fallback_credit（token＋has_prefill_claim=True），其餘欄位與順序一致"


def test_c_refusal_without_token_retries_without_credit():
    client = FakeClient([refusal(token=None), ok("備援回答（無 credit）")])
    msg = cr.manual_fallback_with_credit(client, params(), OPUS)
    first, retry = client.calls
    assert msg.content[0].text == "備援回答（無 credit）" and len(client.calls) == 2
    assert retry["model"] == OPUS and "fallback_credit" not in retry
    assert body_matches(first, retry)
    return "仍然重試到 Opus，但沒有 fallback_credit（會重新寫快取）"


def test_d_served_by_sticky():
    only_fallback = ok("x", iters=("fallback_message",))
    both = ok("x", iters=("message", "fallback_message"))
    only_message = ok("x", iters=("message",))
    empty = NS(usage=NS(iterations=None))
    assert cr.served_by_sticky(only_fallback) is True
    assert cr.served_by_sticky(both) is False
    assert cr.served_by_sticky(only_message) is False
    assert cr.served_by_sticky(empty) is False
    return "只有 fallback_message → True；兩者都有 → False；只有 message → False；iterations=None → False"


def demo_well_meaning_cleanup():
    """錯誤示範：重試前「好心」清掉空字串的 text 區塊，本體就對不上了。"""
    first = params()
    retry = copy.deepcopy(first)
    retry["model"] = OPUS
    retry["fallback_credit"] = {"token": "tok-123", "has_prefill_claim": False}
    for m in retry["messages"]:
        if isinstance(m["content"], list):
            m["content"] = [b for b in m["content"] if b.get("text") != ""]
    good = dict(first, model=OPUS, fallback_credit={"token": "tok-123", "has_prefill_claim": False})
    assert body_matches(first, good) is True
    assert body_matches(first, retry) is False
    reordered = {k: first[k] for k in reversed(first)}  # 只是換欄位順序：dict 相等，但 JSON 字串會不同
    return ("只換 model＋加 credit → body_matches=True；刪掉空字串 text 區塊 → False"
            f"（assistant 區塊數 {len(first['messages'][1]['content'])} → {len(retry['messages'][1]['content'])}）；"
            f"附註：只改欄位順序時 body_matches={body_matches(first, reordered)}，因為它比的是 dict 不是位元組")


def main():
    tests = [
        ("(a) 第一次就成功", test_a_first_call_succeeds),
        ("(b) 拒答＋有 token", test_b_refusal_with_token_retries_with_exact_body),
        ("(c) 拒答＋沒有 token", test_c_refusal_without_token_retries_without_credit),
        ("(d) served_by_sticky", test_d_served_by_sticky),
        ("(e) body_matches 抓到好心清洗", demo_well_meaning_cleanup),
    ]
    for name, fn in tests:
        print(f"ok  {name}：{fn()}")
    print(f"\n{len(tests)}/{len(tests)} 通過（0 次模型呼叫）")


if __name__ == "__main__":
    main()
