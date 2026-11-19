"""第 16 章練習 1：產生 week1／week2 兩份假 log（格式同 fable_scanner/examples/refusal_log.jsonl）。

固定亂數種子，重跑結果相同。
"""
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent
PROMPTS = {
    "ok": "Refactor to typed. Return only the code.",
    "cyber": "Explain how you would fuzz this parser.",
    "reasoning_extraction": "Show your reasoning as you refactor this function.",
    "fallback": "Explain how you would identify the CVE in this parser.",
}


def record(kind, ts):
    req = {"model": "claude-fable-5", "messages": [{"role": "user", "content": PROMPTS[kind]}]}
    fable_it = {"type": "message", "model": "claude-fable-5", "input_tokens": 40}
    if kind == "ok":
        resp = {"model": "claude-fable-5", "stop_reason": "end_turn",
                "usage": {"iterations": [dict(fable_it, output_tokens=260)]}}
    elif kind == "fallback":
        resp = {"model": "claude-opus-4-8", "stop_reason": "end_turn",
                "usage": {"iterations": [dict(fable_it, output_tokens=0),
                                         {"type": "fallback_message", "model": "claude-opus-4-8",
                                          "input_tokens": 220, "output_tokens": 480}]}}
    else:
        resp = {"model": "claude-fable-5", "stop_reason": "refusal", "stop_details": {"category": kind},
                "usage": {"iterations": [dict(fable_it, output_tokens=0)]}}
    return {"timestamp": ts.strftime("%Y-%m-%dT%H:%M:%SZ"), "request": req, "response": resp}


def write_week(name, total, counts, start, seed):
    kinds = [k for k, n in counts.items() for _ in range(n)]
    kinds += ["ok"] * (total - len(kinds))
    random.Random(seed).shuffle(kinds)
    step = timedelta(days=7) / total
    with (OUT / name).open("w", encoding="utf-8") as f:
        for i, kind in enumerate(kinds):
            f.write(json.dumps(record(kind, start + i * step)) + "\n")
    print(f"{name}：{total} 筆 {counts}")


if __name__ == "__main__":
    t0 = datetime(2026, 11, 2, tzinfo=timezone.utc)
    write_week("week1.jsonl", 200, {"cyber": 4, "reasoning_extraction": 2}, t0, seed=1)
    write_week("week2.jsonl", 1000, {"cyber": 20, "reasoning_extraction": 30, "fallback": 15}, t0 + timedelta(days=7), seed=2)
