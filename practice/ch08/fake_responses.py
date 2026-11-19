"""第 8 章練習 1：四種假回應（SimpleNamespace），test_read.py 與 status_only.py 共用。

形狀照 refusal_stack.read() 會讀的欄位：stop_reason、stop_details.category、
content[].type/.text、model、usage.iterations[].type/.model/.output_tokens。
"""
from types import SimpleNamespace as NS

FABLE = "claude-fable-5"
OPUS = "claude-opus-4-8"


def _it(kind, model, out):
    return NS(type=kind, model=model, input_tokens=120, output_tokens=out)


def direct_answer():
    """Fable 直接回答。"""
    return NS(model=FABLE, stop_reason="end_turn", stop_details=None,
              content=[NS(type="text", text="快取命中省下一次往返")],
              usage=NS(output_tokens=18, iterations=[_it("message", FABLE, 18)]))


def fallback_served():
    """Fable 被分類器擋下，伺服器端改由 Opus 4.8 回答。"""
    return NS(model=OPUS, stop_reason="end_turn", stop_details=None,
              content=[NS(type="text", text="這是備援模型寫的答案")],
              usage=NS(output_tokens=40, iterations=[_it("message", FABLE, 25), _it("fallback_message", OPUS, 40)]))


def refused_with_category():
    """整條鏈都拒答，有類別。"""
    return NS(model=OPUS, stop_reason="refusal", stop_details=NS(category="cyber"), content=[],
              usage=NS(output_tokens=0, iterations=[_it("message", FABLE, 31), _it("fallback_message", OPUS, 12)]))


def refused_no_details():
    """整條鏈都拒答，stop_details 是 None（類別對不上任何已命名的類別）。"""
    return NS(model=FABLE, stop_reason="refusal", stop_details=None, content=[],
              usage=NS(output_tokens=0, iterations=[_it("message", FABLE, 9)]))


# (情境名, 工廠函式, HTTP 狀態) —— 四種在 HTTP 層都是 200
SCENARIOS = [
    ("Fable 直接回答", direct_answer, 200),
    ("備援接住", fallback_served, 200),
    ("全部拒答＋類別", refused_with_category, 200),
    ("全部拒答＋stop_details=None", refused_no_details, 200),
]
