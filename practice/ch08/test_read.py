"""第 8 章練習 1：用四種假回應走完 refusal_stack.read() 的每個分支（不呼叫模型）。"""
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import claude_cli_client  # noqa: E402

claude_cli_client.install()  # refusal_stack 在模組層建立 client = Anthropic()，裝了轉接層才不需要金鑰
import refusal.refusal_stack as rs  # noqa: E402
import fake_responses as fr  # noqa: E402

EXPECTED = {
    "Fable 直接回答": ("快取命中省下一次往返", "claude-fable-5 (direct)"),
    "備援接住": ("這是備援模型寫的答案", "claude-opus-4-8"),
    "全部拒答＋類別": (None, "refused (category=cyber)"),
    "全部拒答＋stop_details=None": (None, "refused (category=None)"),
}


def main():
    passed = 0
    for name, factory, _status in fr.SCENARIOS:
        got = rs.read(factory())
        want = EXPECTED[name]
        assert got == want, f"{name}：預期 {want!r}，實際 {got!r}"
        passed += 1
        print(f"ok  {name:<28} → text={got[0]!r}  provenance={got[1]!r}")
    assert claude_cli_client.calls_made() == 0, "read() 不應該呼叫模型"
    print(f"\n{passed}/{len(fr.SCENARIOS)} 個情境通過；claude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
