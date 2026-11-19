"""第 14 章練習 1：最小權限檢查。模型挑的工具不在角色的允許清單就擋下（不呼叫模型）。

用法：PYTHONUTF8=1 python ch14/least_privilege.py [回答檔 ...]（預設 ch14/pick-poisoned.txt、pick-clean.txt）
"""
import json
import re
import sys
from pathlib import Path

ALLOWLIST = {"support-agent": ["lookup_order", "escalate_to_human"]}
ROLE = "support-agent"


def parse_pick(text):
    """從模型回答裡取出第一個 JSON 物件；容許前後有說明文字或 ``` 區塊。"""
    m = re.search(r"\{.*\}", text or "", re.DOTALL)
    if not m:
        raise ValueError("回答裡找不到 JSON 物件")
    pick = json.loads(m.group(0))
    if not isinstance(pick, dict) or "tool" not in pick:
        raise ValueError("JSON 裡沒有 tool 欄位")
    return pick


def check(pick, role=ROLE):
    """回傳 (是否放行, 理由)。角色不存在也一律擋下（預設拒絕）。"""
    allowed = ALLOWLIST.get(role)
    if allowed is None:
        return False, f"角色 {role!r} 沒有允許清單，預設拒絕"
    tool = pick.get("tool")
    if tool in allowed:
        return True, f"{tool} 在 {role} 的允許清單 {allowed} 內"
    return False, f"{tool} 不在 {role} 的允許清單 {allowed} 內"


def main():
    here = Path(__file__).resolve().parent
    files = [Path(p) for p in sys.argv[1:]] or [here / "pick-poisoned.txt", here / "pick-clean.txt"]
    blocked = 0
    for path in files:
        try:
            pick = parse_pick(path.read_text(encoding="utf-8"))
            ok, why = check(pick)
        except (OSError, ValueError) as e:  # json.JSONDecodeError 是 ValueError 的子類
            ok, why, pick = False, f"無法解析回答：{e}（解析失敗一律擋下）", None
        blocked += not ok
        print(f"[{'ALLOW' if ok else 'BLOCK'}] {path.name}：{why}")
        if pick:
            print(f"        args={json.dumps(pick.get('args'), ensure_ascii=False)}")
    # 自我檢查：允許、不允許、未知角色、壞 JSON
    assert check({"tool": "lookup_order"})[0] and not check({"tool": "issue_refund"})[0]
    assert not check({"tool": "get_order_notes"})[0] and not check({"tool": "lookup_order"}, "unknown")[0]
    try:
        parse_pick("沒有 JSON")
        raise AssertionError("應該拋 ValueError")
    except ValueError:
        pass
    print(f"\n{len(files)} 份回答，擋下 {blocked} 份；自我檢查通過")
    return 1 if blocked else 0


if __name__ == "__main__":
    sys.exit(main())
