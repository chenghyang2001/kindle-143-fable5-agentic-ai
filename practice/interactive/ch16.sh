#!/bin/bash
# K143 第 16 章互動演練：錯誤儀表板看不見的拒答——monitor、比率告警與資料源盲區，一次跑一步
# 用法：bash ch16.sh <步驟 1-8>
# 只有第 7 步會真的呼叫模型（2 次）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 不設 K143_CLI_MODEL：monitor 的價目表只認 claude-fable-5 這類完整名稱
# 所有產出寫到 ch16/interactive/，fable5/ 一個檔都不改、也不寫入；ch16/ 底下學習者自己的檔案不碰
set -u
# 轉接層每次呼叫才讀這個上限；第 7 步共 2 次，設 6 留一點餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch16/interactive"   # 動手產生的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 16 章｜看不見的拒答　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
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

# 第 3、6 步共用：用程式產生 monitor 讀得懂的 log（每次覆寫，重跑可重現）
# 注意：py_run 的 heredoc 沒加引號，這段程式不可出現錢字號、反引號與單引號
GEN_PY='import json
from pathlib import Path
from fable_scanner.monitor import analyze
work = Path("../ch16/interactive").resolve()
work.mkdir(parents=True, exist_ok=True)
PROMPTS = {
    "ok": "請把這則告警摘要成三行",
    "cyber": "分析這段可疑流量裡的攻擊手法",
    "reasoning_extraction": "把你的完整推理過程逐步寫出來",
    "fallback": "解釋這個 CVE 的影響範圍",
}

def rec(kind, day):
    it = {"type": "message", "model": "claude-fable-5", "input_tokens": 40, "output_tokens": 120}
    resp = {"model": "claude-fable-5", "stop_reason": "end_turn", "usage": {"iterations": [it]}}
    if kind in ("cyber", "reasoning_extraction"):
        it["output_tokens"] = 0
        resp["stop_reason"] = "refusal"
        resp["stop_details"] = {"category": kind}
    elif kind == "fallback":
        it["output_tokens"] = 0
        resp["model"] = "claude-opus-4-8"
        resp["usage"]["iterations"].append({"type": "fallback_message", "model": "claude-opus-4-8", "input_tokens": 200, "output_tokens": 300})
    req = {"model": "claude-fable-5", "messages": [{"role": "user", "content": PROMPTS[kind]}]}
    return {"timestamp": day + "T09:00:00Z", "request": req, "response": resp}

def write(name, total, plan, day):
    kinds = []
    for kind, n in plan.items():
        kinds += [kind] * n
    kinds += ["ok"] * (total - len(kinds))
    lines = [json.dumps(rec(k, day), ensure_ascii=False) for k in kinds]
    (work / name).write_text("\n".join(lines) + "\n", encoding="utf-8")   # 覆寫，重跑可重現
    return analyze(lines)

def brief(name, s):
    c = s["by_category"]
    print("  " + name + "：total " + str(s["total"]) + "｜refused " + str(s["refused"]) + "｜fallback " + str(s["fallback_served"]) + "｜cyber " + str(c["cyber"]) + "｜reasoning_extraction " + str(c["reasoning_extraction"]))
'

# 第 4～7 步共用：次數、比率與兩種告警
DRIFT_PY='import json
from pathlib import Path
from fable_scanner.monitor import analyze, CATEGORIES
work = Path("../ch16/interactive").resolve()
work.mkdir(parents=True, exist_ok=True)
KEYS = CATEGORIES + ["fallback"]

def load(name):
    p = work / name
    if not p.exists():
        raise SystemExit("找不到 " + str(p) + "，先跑第 3 步")
    return analyze(p.read_text(encoding="utf-8").splitlines())

def counts(stats):
    out = dict(stats["by_category"])
    out["fallback"] = stats["fallback_served"]
    return out

def rates(stats):
    total = stats["total"] or 1
    return {k: v / total for k, v in counts(stats).items()}

def pct(x):
    return format(x * 100, ".2f") + "%"

def naive(stats, limit=10):
    return [k for k, v in counts(stats).items() if v > limit]

def ratio_alert(prev, cur, pp=0.01, mult=2.0):
    a, b = rates(prev), rates(cur)
    return [k for k in KEYS if b[k] - a[k] >= pp or (a[k] > 0 and b[k] >= a[k] * mult)]

def ratio_table(prev, cur):
    a, b = rates(prev), rates(cur)
    rows = []
    for k in KEYS:
        times = format(b[k] / a[k], ".1f") + " 倍" if a[k] > 0 else "上週為 0"
        rows.append("  " + k.ljust(22) + pct(a[k]).rjust(7) + " → " + pct(b[k]).rjust(7) + "｜差 " + format((b[k] - a[k]) * 100, "+.2f") + " 個百分點｜" + times)
    return rows
'

case "$STEP" in
1) banner "認識主角：fable_scanner monitor 只讀本機 log，不連網"
   tip "monitor 不打 API，只讀每行一筆的回應 log。它從 stop_reason、stop_details.category、usage.iterations 裡的 fallback_message 這三個欄位，算出拒答數、各類別數和備援次數。欄位沒記下來，就什麼都看不到。"
   P='sed -n "1,8p;19p;32,72p" fable_scanner/monitor.py
echo "──── 三個關鍵欄位出現在哪 ────"
grep -n "stop_reason\|stop_details\|fallback_message" fable_scanner/monitor.py'
   show "$P"; sh_run "$P" ;;
2) banner "同一份 log，傳統錯誤儀表板 vs monitor"
   tip "拒答不是錯誤：範例 4 筆在 HTTP 層面全部成功，只數例外或 5xx 的儀表板會顯示 0 個錯誤；monitor 卻看得出 2 筆拒答、1 筆其實是備援模型回答的。"
   P='import json
from fable_scanner import monitor
path = "fable_scanner/examples/refusal_log.jsonl"
lines = open(path, encoding="utf-8").read().splitlines()
print("筆｜HTTP｜stop_reason｜類別｜回應模型｜由備援服務")
for i, line in enumerate(lines, 1):
    r = json.loads(line)["response"]
    cat = (r.get("stop_details") or {}).get("category") or "－"
    fb = any(it.get("type") == "fallback_message" for it in r["usage"]["iterations"])
    print(str(i) + "｜200｜" + r["stop_reason"] + "｜" + cat + "｜" + r["model"] + "｜" + ("是" if fb else "否"))
print()
print("傳統錯誤儀表板（只數非 2xx 與例外）：錯誤 0 / " + str(len(lines)) + " → 全綠 ✅")
print()
print("──── monitor 的報表 ────")
monitor.main([path])'
   show "$P"; py_run "$P" ;;
3) banner "動手做：產生 week1（200 筆）與 week2（1000 筆）"
   tip "用程式造兩週的資料（不手打）。week2 流量是 week1 的 5 倍：cyber 拒答跟著流量變 5 倍；reasoning_extraction 是真的變多；另有 15 筆由 claude-opus-4-8 備援服務。最後用 monitor 本身驗算。檔案寫到 ch16/interactive/，每次重跑都覆寫。"
   P='w1 = write("week1.jsonl", 200, {"cyber": 4, "reasoning_extraction": 2}, "2026-11-02")
w2 = write("week2.jsonl", 1000, {"cyber": 20, "reasoning_extraction": 30, "fallback": 15}, "2026-11-09")
print("產生到 " + str(work))
brief("week1.jsonl", w1)
brief("week2.jsonl", w2)
print()
print("──── 用 monitor 的報表看 week2 ────")
from fable_scanner.monitor import print_report
print_report(w2)'
   show "$GEN_PY
$P"; py_run "$GEN_PY
$P" ;;
4) banner "找缺口：「任一類別次數 > 10 就告警」"
   tip "用絕對次數設告警：流量一變 5 倍，cyber 次數自然從 4 變 20，天真版就響了，但這不是事故。需要先跑過第 3 步。"
   P='w1, w2 = load("week1.jsonl"), load("week2.jsonl")
c1, c2 = counts(w1), counts(w2)
print("總請求：week1 " + str(w1["total"]) + "｜week2 " + str(w2["total"]) + "（流量變 " + str(w2["total"] // w1["total"]) + " 倍）")
print()
print("  類別".ljust(24) + "week1 次數  week2 次數")
for k in KEYS:
    print("  " + k.ljust(22) + str(c1[k]).rjust(8) + str(c2[k]).rjust(11))
print()
for name, s in (("week1", w1), ("week2", w2)):
    hits = naive(s)
    print("天真版告警（任一類別次數 > 10）" + name + "：" + ("🔔 " + "、".join(hits) if hits else "無告警"))
print()
print("cyber 從 4 次變 20 次（5 倍），但總流量也是 5 倍——這是流量造成的，不是事故。")'
   show "$DRIFT_PY
$P"; py_run "$DRIFT_PY
$P" ;;
5) banner "改用比率：比上週高 1 個百分點以上，或高到 2 倍以上才告警"
   tip "把每個類別換算成「佔總請求的比率」再跟上週比：cyber 比率根本沒變（是流量造成的），reasoning_extraction 從 1% 漲到 3% 才是真漂移，備援比率從 0 變 1.5% 也是新訊號。結果存成 ch16/interactive/drift.txt。"
   P='w1, w2 = load("week1.jsonl"), load("week2.jsonl")
lines = ["比率漂移（week1 → week2）"] + ratio_table(w1, w2)
lines.append("")
hits_n = naive(w2)
hits_r = ratio_alert(w1, w2)
lines.append("天真版（次數 > 10）：" + ("🔔 " + "、".join(hits_n) if hits_n else "無告警"))
lines.append("比率版（比上週高 ≥ 1 個百分點，或 ≥ 2 倍）：" + ("🔔 " + "、".join(hits_r) if hits_r else "無告警"))
lines.append("天真版誤報、比率版放過的：" + ("、".join(k for k in hits_n if k not in hits_r) or "無"))
out = work / "drift.txt"
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
print()
print("已寫入 " + str(out))'
   show "$DRIFT_PY
$P"; py_run "$DRIFT_PY
$P" ;;
6) banner "實驗：天真版同時會誤報和漏報"
   tip "再造兩週資料、都跟 week1 比。A 週流量尖峰 10 倍、比率不變，天真版照樣響（誤報）；B 週只有 50 筆，cyber 4 次沒過門檻，天真版不響，但比率從 2% 跳到 8%（漏報）。補充：樣本太小時比率會跳來跳去，正式環境要再加最低樣本數條件。"
   P='w1 = load("week1.jsonl")
spike = write("week3_spike.jsonl", 2000, {"cyber": 40, "reasoning_extraction": 20}, "2026-11-16")
small = write("week4_small.jsonl", 50, {"cyber": 4}, "2026-11-23")
for title, s in (("情境 A：流量尖峰 10 倍、比率不變", spike), ("情境 B：週末小流量、cyber 真的變高", small)):
    print("──── " + title + " ────")
    brief("本週", s)
    for row in ratio_table(w1, s):
        print(row)
    hn, hr = naive(s), ratio_alert(w1, s)
    print("  天真版：" + ("🔔 " + "、".join(hn) if hn else "無告警") + "｜比率版：" + ("🔔 " + "、".join(hr) if hr else "無告警"))
    print()
print("A：天真版誤報（流量尖峰不是事故）；B：天真版漏報（4 次沒過門檻，但比率從 2% 跳到 8%）。")'
   show "$GEN_PY
$DRIFT_PY
$P"; py_run "$GEN_PY
$DRIFT_PY
$P" ;;
7) banner "真的呼叫 2 次，看轉接層紀錄的盲區，再寫出 Prometheus 告警規則"
   tip "會呼叫模型 2 次（一則一般提示、一則資安分析），約需 1～3 分鐘；不管有沒有被拒都照實呈現。紀錄寫到 ch16/interactive/real-calls.jsonl 交給 monitor 分析，再匯出比率告警要用的 counter。轉接層紀錄的 stop_details 永遠是 None、也沒有伺服器端備援，所以類別與備援一定是 0——那是資料源沒記，不是沒有拒答。"
   P='import os
import claude_cli_client
import anthropic
log = work / "real-calls.jsonl"
if log.exists():
    log.unlink()                                   # 舊 log 會讓次數算錯
os.environ["K143_CLI_LOG"] = str(log)              # 轉接層每次呼叫才讀，設在這裡就生效
from refusal.refusal_stack import call, read      # 一 import 就建立 Anthropic()，py_run 已先 install()
prompts = [
    "Write a haiku about caches.",
    "As a SOC analyst, describe at a high level what a failed SSH brute-force pattern looks like in auth logs.",
]
for p in prompts:
    try:
        text, who = read(call(p, effort="low"))
        print("  來源：" + who + "｜" + " ".join((text or "（無內容）").split())[:50])
    except anthropic.APIError as exc:
        print("  ❌ 呼叫模型失敗：" + str(exc)[:120])
print("claude -p 呼叫次數：" + str(claude_cli_client.calls_made()))
print()
real = analyze(log.read_text(encoding="utf-8").splitlines() if log.exists() else [])
unknown = real["refused"] - sum(real["by_category"].values())
print("──── 匯出成 Prometheus counter（比率告警需要的兩個指標）────")
print("llm_requests_total " + str(real["total"]))
for k in CATEGORIES:
    print("llm_refusals_total{category=" + json.dumps(k) + "} " + str(real["by_category"][k]))
print("llm_refusals_total{category=" + json.dumps("unknown") + "} " + str(unknown) + "   ← 拒答了卻沒有類別")
print("llm_fallback_served_total " + str(real["fallback_served"]))
print()
print("為什麼類別與備援一定是 0：轉接層寫 log 時 stop_details 固定是 None，claude -p 也沒有伺服器端備援（不會有 fallback_message）。")
print("→ 監控只看得到「有被記錄的欄位」，資料源沒記，儀表板就永遠是 0。")
rule = """groups:
- name: llm-refusal-drift
  rules:
  - alert: RefusalRateDrift
    expr: |
      sum by (category) (increase(llm_refusals_total[7d]))
        / ignoring(category) group_left sum(increase(llm_requests_total[7d]))
      -
      sum by (category) (increase(llm_refusals_total[7d] offset 7d))
        / ignoring(category) group_left sum(increase(llm_requests_total[7d] offset 7d))
      > 0.01
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: 某拒答類別佔總請求的比率比上週高 1 個百分點以上
"""
out = work / "prometheus-rule.yml"
out.write_text(rule, encoding="utf-8")
print()
print("──── 比率告警規則草稿（已寫入 " + str(out) + "）────")
print(rule)'
   show "$DRIFT_PY
$P"; py_run "$DRIFT_PY
$P" ;;
8) banner "總結：拒答要被記錄，告警要看比率"
   tip "拒答是 HTTP 200，傳統錯誤儀表板看不見。要看得見，遙測得記下對的欄位；要不誤報也不漏報，告警得看比率。"
   P='cat <<EOF
  第 16 章總結
    拒答藏在 HTTP 200 裡：只數例外和 5xx 的儀表板會一片綠燈（第 2 步 4 筆裡有 2 筆拒答、1 筆是備援回答的）
    要看得見，遙測就得記下三個欄位：stop_reason、拒答類別（stop_details.category）、實際服務的模型／fallback_message
    告警看比率、不看次數：流量尖峰會讓次數暴增造成誤報，小流量時真的漂移又會因為次數不夠而漏報
    cyber 次數多了 5 倍但比率不變，是流量造成的；reasoning_extraction 從 1% 漲到 3%，才是真漂移
    資料源本身也有盲區：轉接層紀錄沒有類別也沒有備援，所以 0 不等於沒事
    分類器更新時你的程式一行都沒改，拒答率照樣會漂移，所以 monitor、金絲雀和比率告警要一直開著
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch16.sh <步驟 1-8>"; exit 1 ;;
esac
