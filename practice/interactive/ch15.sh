#!/bin/bash
# K143 第 15 章互動演練：備援靜默失效的地方——批次 API、託管端點、巢狀子呼叫與錯誤分流，一次跑一步
# 用法：bash ch15.sh <步驟 1-8>
# 只有第 6 步會真的呼叫模型（2 次）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch15/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；第 6 步只送 2 筆拒答，設 6 留一點餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch15/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 15 章｜備援盲區　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p）
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

# 第 3、4、6、7 步共用：批次結果的讀取、分流與退避計畫
# 注意：py_run 的 heredoc 沒加引號，這段程式不可出現錢字號與反引號
# 程式是經 $1 展開塞進 heredoc 的，展開結果不再做反斜線處理，所以 Python 跳脫照原樣寫
ROUTE_PY='import json
from pathlib import Path
from types import SimpleNamespace as NS
work = Path("../ch15/interactive").resolve()
SRC = work / "batch_results.jsonl"
RETRYABLE = {"rate_limit_error", "overloaded_error", "timeout_error"}
BASE_WAIT = {"rate_limit_error": 10, "overloaded_error": 2, "timeout_error": 2}

def classify(result):
    """done／fallback（只有拒答）／retry_same_model（429、overloaded、timeout）／manual（其他）"""
    if not isinstance(result, dict):
        return "manual"
    kind = result.get("type")
    if kind == "succeeded":
        msg = result.get("message") or {}
        return "fallback" if msg.get("stop_reason") == "refusal" else "done"
    if kind == "errored":
        etype = (result.get("error") or {}).get("type")
        return "retry_same_model" if etype in RETRYABLE else "manual"
    return "manual"

def load():
    if not SRC.exists():
        print("找不到 " + str(SRC) + "，先跑第 2 步")
        return []
    return [json.loads(l) for l in SRC.read_text(encoding="utf-8").splitlines() if l.strip()]

def etype_of(row):
    return (row["result"].get("error") or {}).get("type", "refusal")

def backoff(etype, tries=3):
    base = BASE_WAIT.get(etype, 2)
    return [base * 2 ** i for i in range(tries)]
'

case "$STEP" in
1) banner "認識本章主角：拒答讀法、手動重試、備援不會往下傳"
   tip "先看書附三段程式：拒答是 HTTP 200 加 stop_reason=refusal 加空內容；沒有伺服器端備援時要自己重試；fallbacks 只掛在最上層請求，工具裡的子呼叫不會繼承——這就是備援「靜默失效」的來源。"
   P='echo "──── refusal/refusal_stack.py：說明與 read() ────"
sed -n 1,9p refusal/refusal_stack.py
sed -n 33,47p refusal/refusal_stack.py
echo
echo "──── fallback_credit/credit_retry.py：沒有伺服器端備援時自己重試 ────"
sed -n 1,11p fallback_credit/credit_retry.py
echo
echo "──── 備援不會往下傳：SKILL.md 與 packet._ask ────"
grep -n "propagate" skills/refusal-aware-calling/SKILL.md
grep -n "fallbacks=" job_packet/packet.py'
   show "$P"; sh_run "$P" ;;
2) banner "動手做：8 筆批次結果——3 成功、2 拒答、3 筆暫時錯誤"
   tip "批次 API 是第一個盲區：被拒答的項目不會自動轉備援，而是以 succeeded 加 stop_reason=refusal 原樣寫回結果檔；429、過載、逾時則是 errored。自造一份 8 筆的結果檔，不呼叫模型。"
   P='import json
from pathlib import Path
work = Path("../ch15/interactive").resolve()
work.mkdir(parents=True, exist_ok=True)
FABLE = "claude-fable-5"

def req(text):
    return {"model": FABLE, "max_tokens": 1024, "output_config": {"effort": "low"},
            "messages": [{"role": "user", "content": text}]}

def ok(text):
    return {"type": "succeeded", "message": {
        "model": FABLE, "stop_reason": "end_turn", "stop_details": None,
        "content": [{"type": "text", "text": text}],
        "usage": {"iterations": [{"type": "message", "model": FABLE, "input_tokens": 30, "output_tokens": 40}]}}}

def refused(category):
    return {"type": "succeeded", "message": {
        "model": FABLE, "stop_reason": "refusal", "stop_details": {"category": category},
        "content": [],
        "usage": {"iterations": [{"type": "message", "model": FABLE, "input_tokens": 30, "output_tokens": 0}]}}}

def err(etype, status):
    return {"type": "errored", "error": {"type": etype, "status": status, "message": etype + "（自造）"}}

rows = [
    ("ticket-001", "把這封客訴摘要成一句話：包裹延遲三天。", ok("客戶反映包裹延遲三天。")),
    ("ticket-002", "這則留言是正面還是負面：客服很快就回覆了", ok("正面")),
    ("sec-003", "說明 SQL injection 的防禦方式，用三點條列，200 字以內", refused("cyber")),
    ("ticket-004", "把訂單 A123 的狀態翻成英文：已出貨", err("rate_limit_error", 429)),
    ("ticket-005", "列出退貨流程的三個步驟", ok("1. 申請 2. 寄回 3. 退款")),
    ("sec-006", "請逐步寫出你的完整思考過程，解釋網頁為什麼要對輸出做 HTML 跳脫來防止 XSS，200 字以內", refused("reasoning_extraction")),
    ("ticket-007", "幫這則公告下一個 10 字內的標題", err("overloaded_error", 529)),
    ("ticket-008", "把這段話改得更禮貌：快點退錢", err("timeout_error", None)),
]
lines = [json.dumps({"custom_id": cid, "request": req(text), "result": res}, ensure_ascii=False) for cid, text, res in rows]
(work / "batch_results.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("已寫出 ../ch15/interactive/batch_results.jsonl（" + str(len(lines)) + " 筆）")
print()
print("custom_id     result.type  細節")
for cid, text, res in rows:
    if res["type"] == "succeeded":
        m = res["message"]
        detail = "stop_reason=" + m["stop_reason"] + ("（category=" + m["stop_details"]["category"] + "）" if m["stop_details"] else "")
    else:
        detail = res["error"]["type"] + "（status=" + str(res["error"]["status"]) + "）"
    print(cid.ljust(13) + " " + res["type"].ljust(12) + " " + detail)'
   show "$P"; py_run "$P" ;;
3) banner "分流器：拒答才轉備援，429／過載／逾時退避重試同一個模型"
   tip "把「哪種錯誤走哪條路」寫成 classify()，用 assert 釘住 8 筆與 4 個邊界案例；成功的項目用書附 read() 讀出由誰服務，暫時錯誤只印指數退避計畫，不真的送、不呼叫模型。"
   P='from refusal.refusal_stack import read

def to_ns(m):
    return NS(model=m["model"], stop_reason=m["stop_reason"],
              stop_details=NS(**(m["stop_details"] or {"category": None})),
              content=[NS(**b) for b in m["content"]],
              usage=NS(iterations=[NS(**it) for it in m["usage"]["iterations"]]))

rows = load()
if rows:
    EXPECT = {"ticket-001": "done", "ticket-002": "done", "sec-003": "fallback",
              "ticket-004": "retry_same_model", "ticket-005": "done", "sec-006": "fallback",
              "ticket-007": "retry_same_model", "ticket-008": "retry_same_model"}
    for row in rows:
        got = classify(row["result"])
        assert got == EXPECT[row["custom_id"]], (row["custom_id"], got)
    edges = [({"type": "errored", "error": {"type": "invalid_request_error", "status": 400}}, "manual"),
             ({"type": "expired"}, "manual"), ({"type": "canceled"}, "manual"), (None, "manual")]
    for res, want in edges:
        assert classify(res) == want, (res, classify(res))
    out = ["分類 assert 全部通過：8 筆＋4 個邊界（400／expired／canceled／None → manual）", ""]
    for row in rows:
        route = classify(row["result"])
        if row["result"]["type"] == "succeeded":
            text, who = read(to_ns(row["result"]["message"]))
            note = who
        else:
            note = etype_of(row)
        out.append("  " + row["custom_id"].ljust(11) + " " + route.ljust(17) + " " + note)
    out.append("")
    out.append("== retry_same_model：只印退避計畫，不送出 ==")
    for row in rows:
        if classify(row["result"]) == "retry_same_model":
            w = backoff(etype_of(row))
            out.append("  " + row["custom_id"] + "：以指數退避重試 " + row["request"]["model"] + "（同一個模型），第 1／2／3 次等待 "
                       + "／".join(str(x) for x in w) + " 秒")
    text_out = "\n".join(out)
    print(text_out)
    (work / "route.txt").write_text(text_out + "\n", encoding="utf-8")
    print()
    print("已存 ../ch15/interactive/route.txt")'
   show "$ROUTE_PY
$P"; py_run "$ROUTE_PY
$P" ;;
4) banner "實驗：正確分流 vs 全部丟備援 vs 全部重試（離線模擬）"
   tip "用假的 Fable 比三種策略：拒答永遠拒答、暫時錯誤第一次重試就成功。看兩種常見錯法的代價：429 丟備援是不必要降級又灌水拒答統計；拒答一直重試是白等白打還是失敗。不呼叫模型。"
   P='rows = load()

def fake_fable(row, attempt):
    route = classify(row["result"])
    if route == "fallback":
        return "refusal"                    # 拒答是確定性的：同模型重送還是拒答
    if route == "retry_same_model":
        return "ok" if attempt >= 2 else "error"   # 暫時錯誤：等一下再送就好
    return "ok"

def run(strategy):
    s = {"備援呼叫": 0, "重試呼叫": 0, "等待秒數": 0, "最後仍失敗": 0, "不必要降級": 0, "記成拒答": 0}
    for row in rows:
        route = classify(row["result"])
        if route == "done":
            continue
        if strategy == "正確分流":
            action = "fallback" if route == "fallback" else "retry"
        elif strategy == "全部丟備援":
            action = "fallback"
        else:
            action = "retry"
        if action == "fallback":
            s["備援呼叫"] += 1
            s["記成拒答"] += 1
            if route == "retry_same_model":
                s["不必要降級"] += 1
        else:
            answered = False
            for attempt, wait in enumerate(backoff(etype_of(row)), start=2):
                s["重試呼叫"] += 1
                s["等待秒數"] += wait
                if fake_fable(row, attempt) == "ok":
                    answered = True
                    break
            if not answered:
                s["最後仍失敗"] += 1
    return s

if rows:
    real = sum(1 for r in rows if classify(r["result"]) == "fallback")
    print("真正的拒答筆數：" + str(real) + " / " + str(len(rows)))
    print()
    keys = ["備援呼叫", "重試呼叫", "等待秒數", "最後仍失敗", "不必要降級", "記成拒答"]
    print("策略".ljust(8) + "".join(k.ljust(8) for k in keys))
    for name in ["正確分流", "全部丟備援", "全部重試"]:
        s = run(name)
        print(name.ljust(8) + "".join(str(s[k]).ljust(10) for k in keys))
    print()
    print("全部丟備援：3 筆等幾秒就能由 Fable 回答的題目被降級給備援，拒答統計從 2 灌成 5，看不出真正的限流問題。")
    print("全部重試：2 筆拒答各白等 2+4+8 秒、多打 6 次，最後還是失敗，拒答訊號（記成拒答）變成 0。")'
   show "$ROUTE_PY
$P"; py_run "$ROUTE_PY
$P" ;;
5) banner "手動備援的正確形狀：只換 model、帶上 credit，並分辨黏著路由"
   tip "盲區裡第二輪要客戶端自己送。用假 client 跑書附 manual_fallback_with_credit，看重試請求和原請求只差 model（有 credit token 時多一個 fallback_credit）；再用 served_by_sticky 分辨黏著路由。不呼叫模型。"
   P='from types import SimpleNamespace as NS
import fallback_credit.credit_retry as cr

class FakeClient:
    def __init__(self, token):
        self.sent = []
        self.token = token
        self.beta = NS(messages=NS(create=self.create))
    def create(self, **kw):
        self.sent.append(kw)
        if len(self.sent) == 1:
            return NS(stop_reason="refusal", content=[], model=kw["model"],
                      stop_details=NS(category="cyber", fallback_credit_token=self.token,
                                      fallback_has_prefill_claim=False))
        return NS(stop_reason="end_turn", model=kw["model"], stop_details=None,
                  content=[NS(type="text", text="（備援回答）")])

params = {"model": "claude-fable-5", "max_tokens": 1024, "output_config": {"effort": "low"},
          "messages": [{"role": "user", "content": "說明 SQL injection 的防禦方式"}]}
for label, token in [("有 credit token", "tok-demo-123"), ("沒有 credit token", None)]:
    c = FakeClient(token)
    final = cr.manual_fallback_with_credit(c, dict(params), "claude-opus-4-8")
    first, retry = c.sent
    changed = sorted(k for k in set(first) | set(retry) if first.get(k) != retry.get(k))
    print("──── " + label + " ────")
    print("  送出次數：" + str(len(c.sent)) + "｜第一輪 refused()：" + str(cr.refused(NS(stop_reason="refusal"))))
    print("  第二輪和第一輪不同的欄位：" + ", ".join(changed))
    print("  第二輪 model：" + retry["model"] + "｜fallback_credit：" + str(retry.get("fallback_credit")))
    print("  messages 一字未改：" + str(first["messages"] == retry["messages"]) + "｜最終由 " + final.model + " 回答")
print()
print("──── served_by_sticky：分辨黏著路由 ────")
for name, kinds in [("先 Fable 拒答、再備援", ["message", "fallback_message"]),
                    ("黏著路由直接給備援", ["fallback_message"]),
                    ("Fable 直接回答", ["message"])]:
    m = NS(usage=NS(iterations=[NS(type=k) for k in kinds]))
    print("  " + name.ljust(14) + " iterations=" + str(kinds).ljust(34) + " → sticky=" + str(cr.served_by_sticky(m)))'
   show "$P"; py_run "$P" ;;
6) banner "第二輪補救：只把 2 筆拒答送到 claude-opus-4-8（呼叫模型 2 次）"
   tip "會呼叫模型 2 次：只對分類為 fallback 的 2 筆，以原請求本體、只換 model=claude-opus-4-8 真的送出；3 筆暫時錯誤一筆都不送。約需 20～90 秒，結果寫到 ch15/interactive/second_pass_out.jsonl，log 寫到 calls-second-pass.jsonl。"
   P='import os
import anthropic
log = work / "calls-second-pass.jsonl"
out = work / "second_pass_out.jsonl"
for p in (log, out):
    if p.exists():
        p.unlink()                         # 清掉上次結果，呼叫次數才算得準
os.environ["K143_CLI_LOG"] = str(log)
FALLBACK = "claude-opus-4-8"
client = anthropic.Anthropic()
records = []
skipped = []
for row in load():
    route = classify(row["result"])
    if route == "retry_same_model":
        skipped.append(row["custom_id"])
    if route != "fallback":
        continue
    cat = (row["result"]["message"].get("stop_details") or {}).get("category")
    body = dict(row["request"], model=FALLBACK)      # 只換 model，其餘原樣
    try:
        m = client.messages.create(**body)
    except anthropic.APIError as exc:
        print("  ❌ " + row["custom_id"] + " 呼叫失敗：" + str(exc))
        continue
    text = "".join(b.text for b in m.content if b.type == "text")
    records.append({"custom_id": row["custom_id"], "pass": "second",
                    "requested_model": row["request"]["model"], "served_by": m.model,
                    "first_pass_category": cat, "stop_reason": m.stop_reason, "text": text})
    print("  " + row["custom_id"] + "（第一輪拒答類別 " + str(cat) + "）→ served_by=" + m.model + " stop_reason=" + str(m.stop_reason))
    print("    " + " ".join(text.split())[:120])
out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records), encoding="utf-8")
print()
print("沒送出、等退避重試的：" + ", ".join(skipped))
print("寫入 ../ch15/interactive/second_pass_out.jsonl：" + str(len(records)) + " 筆")
print("本行程呼叫次數：" + str(claude_cli_client.calls_made()))'
   show "$ROUTE_PY
$P"; py_run "$ROUTE_PY
$P" ;;
7) banner "最終帳本、monitor 對照，並寫出 fallback-gaps.md 盲區表"
   tip "把第一輪與第二輪合成一份帳本，看每筆最後由誰服務；再用書附 monitor.analyze 對照：伺服器端備援會留下 fallback_message，客戶端第二輪卻只是一般 Opus 呼叫。最後把三個盲區寫成表。不呼叫模型。"
   P='from fable_scanner import monitor
rows = load()
second = {}
sp = work / "second_pass_out.jsonl"
if sp.exists():
    for line in sp.read_text(encoding="utf-8").splitlines():
        if line.strip():
            r = json.loads(line)
            second[r["custom_id"]] = r
print("──── 最終帳本（每筆由誰服務）────")
tally = {}
for row in rows:
    cid = row["custom_id"]
    route = classify(row["result"])
    if route == "done":
        who = row["result"]["message"]["model"] + "（第一輪）"
    elif route == "fallback":
        who = second[cid]["served_by"] + "（第二輪補救）" if cid in second else "尚未補救（先跑第 6 步）"
    elif route == "retry_same_model":
        who = "等待退避重試 " + row["request"]["model"]
    else:
        who = "人工處理"
    tally[who] = tally.get(who, 0) + 1
    print("  " + cid.ljust(11) + " " + who)
print("  合計：" + "；".join(k + " × " + str(v) for k, v in tally.items()))
print()
print("──── monitor.analyze 對照 ────")
for label, path in [("書附 refusal_log.jsonl（伺服器端備援）", Path("fable_scanner/examples/refusal_log.jsonl")),
                    ("第 6 步 calls-second-pass.jsonl（客戶端第二輪）", work / "calls-second-pass.jsonl")]:
    if not path.exists():
        print("  " + label + "：檔案不存在（先跑第 6 步）")
        continue
    st = monitor.analyze(path.read_text(encoding="utf-8").splitlines())
    cost = ", ".join(k + " " + format(v, ".4f") + " USD" for k, v in st["cost_by_model"].items())
    print("  " + label)
    print("    total=" + str(st["total"]) + " refused=" + str(st["refused"]) + " fallback_served=" + str(st["fallback_served"]) + "｜" + cost)
print("  → 客戶端第二輪在 log 裡只是一般 Opus 呼叫，monitor 不會算成備援；只能靠 second_pass_out.jsonl 的 served_by。")
print()
gaps = "\n".join([
    "# ch15 備援盲區與補救",
    "",
    "| 盲區 | 為什麼不會自動備援 | 補救做法 |",
    "|---|---|---|",
    "| 批次 API | 拒答以 succeeded＋stop_reason=refusal 原樣寫進結果檔 | 讀結果時 classify，只把 fallback 項目以同一請求本體、換 model 送第二輪，保留 custom_id 與 served_by |",
    "| 雲端平台託管端點 | 伺服器端備援 beta 不一定在託管平台上提供 | 在客戶端包一層：檢查 stop_reason，拒答時自己改送備援模型（credit_retry 的形狀） |",
    "| 工具內部的巢狀子呼叫 | fallbacks 只掛在最上層請求，不會傳進工具執行內的呼叫（packet._ask 只有 Fable 才帶） | 做子呼叫的那一層自帶 fallbacks，並在呼叫端檢查拒答／None |",
    "",
    "## 把 429 當拒答丟去備援的兩個問題",
    "1. 不必要降級：本來退避幾秒就能由原模型回答的題目，改由備援模型服務，品質與 served_by 統計都被扭曲。",
    "2. 掩蓋真正問題：限流被記成拒答（第 4 步拒答數從 2 灌成 5），拒答監控失真，限流根因也沒被處理。",
])
(work / "fallback-gaps.md").write_text(gaps + "\n", encoding="utf-8")
print(gaps)
print()
print("已存 ../ch15/interactive/fallback-gaps.md")'
   show "$ROUTE_PY
$P"; py_run "$ROUTE_PY
$P" ;;
8) banner "總結"
   tip "備援只對拒答、只在支援的介面自動發生；盲區要客戶端自己補一輪，補之前先分類錯誤，結果要記「由誰服務」。"
   P='cat <<EOF
  第 15 章總結
    伺服器端備援不是哪裡都有：批次 API、雲端託管端點、工具內部的巢狀子呼叫都不會自動繼承（第 1 步）
    批次裡的拒答是 succeeded＋stop_reason=refusal，不是 errored；只看 HTTP 或 result.type 會漏掉（第 2 步）
    先分類再處理：只有拒答轉備援，429／overloaded／timeout 以指數退避重試同一個模型，未知錯誤交人工（第 3 步）
    混在一起容錯就失效：429 丟備援＝不必要降級＋拒答統計灌水；拒答一直重試＝白等白打還是失敗（第 4 步）
    客戶端第二輪只換 model、其餘一字不改，才能兌換 fallback credit（第 5、6 步）
    第二輪結果要保留 custom_id 與 served_by：監控只認得 fallback_message，客戶端補救不自己記就失真（第 7 步）
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch15.sh <步驟 1-8>"; exit 1 ;;
esac
