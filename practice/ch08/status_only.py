"""第 8 章練習 1：只看 HTTP 狀態碼的天真錯誤處理器，對同樣四種假回應跑一遍。"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fake_responses as fr  # noqa: E402


def naive_handler(status, msg):
    """典型舊寫法：200 就是成功，直接拿第一個內容區塊。"""
    if status != 200:
        raise RuntimeError(f"HTTP {status}")
    return msg.content[0].text


def naive_join_handler(status, msg):
    """稍微「防禦」一點的舊寫法：把所有 text 區塊串起來（不會 IndexError）。"""
    if status != 200:
        raise RuntimeError(f"HTTP {status}")
    return "".join(b.text for b in msg.content if b.type == "text")


def run(handler, status, msg):
    try:
        return f"回傳 {handler(status, msg)!r}"
    except Exception as e:  # noqa: BLE001 — 這裡就是要觀察它怎麼當掉
        return f"當掉：{type(e).__name__}: {e}"


def main():
    for name, factory, status in fr.SCENARIOS:
        msg = factory()
        print(f"{name}（HTTP {status}，stop_reason={msg.stop_reason}，model={msg.model}）")
        print(f"  content[0].text 版：{run(naive_handler, status, msg)}")
        print(f"  join 版          ：{run(naive_join_handler, status, msg)}")
        print("  兩版都不知道是誰回答的" if name == "備援接住" else "", end="\n" if name == "備援接住" else "")
    print()


if __name__ == "__main__":
    main()
