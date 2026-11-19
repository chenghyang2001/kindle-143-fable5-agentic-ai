"""第 10 章練習 1：我的 effort 路由器。從 fable5/effort/effort_router.py 的 effort_for() 複製後擴充，
加入這場 K143 演練實際遇到的任務類型。每一類的 effort 都附一行理由。
"""
LEVELS = ("low", "medium", "high", "xhigh", "max")

# 任務類型 → (effort, 為什麼)。改政策只要改這張表。
POLICY = {
    # 原版保留
    "classify":       ("low",    "輸出只有一個標籤，沒有分支判斷（ch07 錯誤分類 3 token 就答對）"),
    "extract":        ("low",    "從固定格式抽欄位，答案已經在輸入裡"),
    "format":         ("low",    "純排版轉換，一句話就能說完的工作"),
    "summarize":      ("medium", "要挑重點，但範圍是給定的文字，不需要外部推理"),
    "chat":           ("medium", "一般問答，延遲使用者看得到"),
    "route":          ("medium", "在已知選項裡挑一個，有少量判斷"),
    "migrate":        ("xhigh",  "單向門：改錯了很難回頭"),
    "audit":          ("xhigh",  "要找出沒人寫下來的風險，判斷最密集"),
    "novel-research": ("xhigh",  "要拆題、找反例，沒有現成答案"),
    # 這場演練實際遇到的類型
    "grade":          ("low",    "驗證者只回 PASS／FAIL＋一句理由（ch02 triage verify 與 research_loop 三票都用 low），靠多票換可靠度"),
    "lint-explain":   ("low",    "掃描器已經給出規則代碼與行號，只要把它翻成白話（ch05 規則表）"),
    "write-report":   ("medium", "要讀多份輸出、整理成給沒看過過程的人讀的報告，但事實都已經在檔案裡"),
    "memory-quarantine": ("low", "判斷一個檔是描述還是命令，第一行回 QUARANTINE／PASS（ch03 startup_scan 用 low）"),
    "routing-policy": ("high",   "要權衡成本與品質、找錯路由（ch04 成本儀表板）；不是單向門，用預設 high 就好"),
    "scope-review":   ("xhigh",  "Mythos 式資安範圍審查：漏一個欄位就可能越界，屬於高風險判斷"),
}
DEFAULT = ("high", "沒有分類到的工作用 API 預設值，等有資料再調")


def effort_for(task):
    """回傳 task['kind'] 對應的 effort；未知或缺少 kind 時回 high。"""
    kind = task.get("kind") if isinstance(task, dict) else None
    return POLICY.get(kind, DEFAULT)[0]


def why(kind):
    return POLICY.get(kind, DEFAULT)[1]


if __name__ == "__main__":
    expected = {
        "classify": "low", "extract": "low", "format": "low",
        "summarize": "medium", "chat": "medium", "route": "medium",
        "migrate": "xhigh", "audit": "xhigh", "novel-research": "xhigh",
        "grade": "low", "lint-explain": "low", "write-report": "medium",
        "memory-quarantine": "low", "routing-policy": "high", "scope-review": "xhigh",
    }
    for kind, want in expected.items():
        got = effort_for({"kind": kind})
        assert got == want, f"{kind}: 預期 {want}，實際 {got}"
        assert got in LEVELS
        print(f"ok  {kind:<18} → {got:<6} {why(kind)}")
    # 邊界：未知類型、缺 kind、kind=None、不是 dict
    for task in ({"kind": "something-new"}, {}, {"kind": None}, None):
        assert effort_for(task) == "high", task
    print(f"ok  未知／缺 kind／None／非 dict → high（{DEFAULT[1]}）")
    assert set(POLICY) == set(expected), "POLICY 與測試清單不一致"
    print(f"\n{len(expected)} 種類型＋4 個邊界案例全部通過；分布："
          + "、".join(f"{lv} {sum(v[0] == lv for v in POLICY.values())}" for lv in LEVELS))
