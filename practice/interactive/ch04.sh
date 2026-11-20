#!/bin/bash
# K143 第 4 章互動演練：昂貴規劃，廉價建置——job packet 四段迴圈、成本儀表板與 MCP 稽核，一次跑一步
# 用法：bash ch04.sh <步驟 1-8>
# 第 4 步（2 次）與第 7 步（3 次）會真的呼叫模型：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch04/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；每步是獨立行程，最多一步 3 次，設 6 留一點餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch04/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 4 章｜昂貴規劃，廉價建置　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
# PYTHONDONTWRITEBYTECODE=1：不在 fable5/ 底下產生 __pycache__
sh_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONDONTWRITEBYTECODE=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p）
# packet.py 一 import 就建立 Anthropic()，裝了轉接層只會建立物件、不會呼叫模型
# 注意：py_run 的 heredoc 沒加引號，這段程式不可出現錢字號與反引號（金額一律印成 USD）
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

case "$STEP" in
1) banner "主角登場：一個迴圈、四段、兩種價位"
   tip "packet.py 只有四個函式：prep 與 execute 交給便宜的 Sonnet 5，plan_or_audit 與 verify 才用 Fable 5，而且每段的 effort 預設不同。不呼叫模型。"
   P='import inspect
import job_packet.packet as pk
print(pk.__doc__.strip())
print()
print("FABLE = " + pk.FABLE + "｜CHEAP = " + pk.CHEAP + "｜備援 = " + pk.FALLBACKS[0]["model"])
print()
print("  函式            用哪個模型        effort 預設")
for fn in [pk.prep, pk.plan_or_audit, pk.execute, pk.verify]:
    src = inspect.getsource(fn)
    model = "FABLE（貴）" if "FABLE" in src else "CHEAP（便宜）"
    effort = inspect.signature(fn).parameters["effort"].default
    print("  " + fn.__name__.ljust(15) + " " + model.ljust(14) + " " + effort)'
   show "$P"; py_run "$P" ;;
2) banner "十個專案各走了哪幾段"
   tip "十個週末專案都 import 同一個 job_packet，只是換資料。看每個專案用了四段裡的哪幾段：plan_or_audit 每個都有，成本儀表板連 prep 都沒有。不呼叫模型。"
   P='import re
from pathlib import Path
STAGES = ["prep", "plan_or_audit", "execute", "verify"]
pat = re.compile(r"from job_packet.packet import (.+?)\s+#")
print("專案".ljust(22) + "".join(s.ljust(15) for s in STAGES))
for py in sorted(Path("projects").glob("*/*.py")):
    m = pat.search(py.read_text(encoding="utf-8"))
    if not m:
        continue                      # sample_target.py 這類範例資料不算
    used = [x.strip() for x in m.group(1).split(",")]
    print(py.parent.name.ljust(22) + "".join(("✔" if s in used else "－").ljust(15) for s in STAGES))
print()
print("註：這是看 import 了哪幾段，第 3 步會看 03 的 prep 為什麼不需要模型。")'
   show "$P"; py_run "$P" ;;
3) banner "一句話測試：算術交給 Python，順便做答案卷"
   tip "加總沒有分支、沒有判斷，不必花模型錢。用純 Python 算週摘要，再算 Fable 5 上的小任務改到 Haiku 能省多少，存成 ch04/interactive/answer-key.txt，第 4 步拿來抽驗模型。不呼叫模型。"
   P='import csv, sys
from pathlib import Path
sys.path.insert(0, "projects/03_cost_dashboard")
import cost_dashboard as cd
with open("projects/03_cost_dashboard/sample_usage_log.csv", newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))
print("──── 週摘要（cd.summarize，純 Python）────")
for m, t in cd.summarize(rows).items():
    print("  " + m + ": " + str(t["calls"]) + " calls, " + str(t["tokens"]) + " tokens, USD " + format(t["cost"], ".4f"))
print()

def cost(model, r):
    pi, po = cd.PRICES[model]
    return int(r["input_tokens"]) / 1e6 * pi + int(r["output_tokens"]) / 1e6 * po

SIMPLE = {"typo_fix", "rename_variable", "one_line_summary", "answer_slack_question"}
JUDGE = {"threat_model", "migration_plan"}
lines = ["Fable 5 上的每一筆：留在 Fable vs 改用 Haiku 4.5（USD）"]
week = 0.0
for r in rows:
    if r["model"] != "claude-fable-5":
        continue
    fa, ha = cost("claude-fable-5", r), cost("claude-haiku-4-5", r)
    t = r["task_type"]
    tag = "一句話任務" if t in SIMPLE else ("需要判斷" if t in JUDGE else "可討論")
    if t in SIMPLE:
        week += fa - ha
    lines.append("  " + t.ljust(22) + " Fable " + format(fa, ".5f") + "  Haiku " + format(ha, ".5f") + "  " + tag)
lines.append("四個一句話任務改到 Haiku：每週省 USD " + format(week, ".4f") + "，乘 4 約每月 USD " + format(week * 4, ".4f"))
text = "\n".join(lines)
out = Path("../ch04/interactive/answer-key.txt")
out.write_text(text + "\n", encoding="utf-8")
print(text)
print()
print("答案卷已存到 " + str(out.resolve()))'
   show "$P"; py_run "$P" ;;
4) banner "跑成本儀表板：Fable 設計路由政策、Sonnet 寫報告"
   tip "會呼叫模型 2 次：plan_or_audit 用 Fable 5（effort high）設計路由政策，execute 用 Sonnet 5 寫執行報告，約需 1～3 分鐘。每次呼叫記到 ch04/interactive/calls-03.jsonl，跑完拿第 3 步的答案卷抽驗模型說的金額。輸出裡的 email 會先遮蔽再顯示與存檔。"
   P='rm -f ../ch04/interactive/calls-03.jsonl ../ch04/interactive/run-03.txt
K143_CLI_LOG=../ch04/interactive/calls-03.jsonl python ../run_with_cli.py projects/03_cost_dashboard/cost_dashboard.py 2>&1 | sed -E "s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]+/<email 已遮蔽>/g" | tee ../ch04/interactive/run-03.txt
echo
echo "──── 輸出裡出現的金額（含週摘要與模型報告）────"
grep -oE "[$][0-9][0-9.,]*" ../ch04/interactive/run-03.txt | sort | uniq -c | sort -rn | head -15
echo
echo "──── 答案卷（第 3 步純 Python 算的）────"
cat ../ch04/interactive/answer-key.txt 2>/dev/null || echo "（找不到答案卷，先跑第 3 步）"'
   show "$P"; sh_run "$P" ;;
5) banner "用呼叫紀錄驗證，不聽模型自己說"
   tip "成本要從 log 追，不從模型的文字報告追。讀第 4 步的 calls-03.jsonl、交給 fable_scanner monitor 算，再對照兩張價目表：Sonnet 的價格對不上，而且優惠價已過期。注意：轉接層回報的 token 不等於真實帳單，monitor 算出的金額只是用這些值換算。不呼叫模型。"
   P='import json, sys, datetime
from pathlib import Path
from fable_scanner import monitor as mon
sys.path.insert(0, "projects/03_cost_dashboard")
import cost_dashboard as cd
log = Path("../ch04/interactive/calls-03.jsonl")
if not log.exists():
    print("找不到 " + str(log) + "，先跑第 4 步")
else:
    lines = log.read_text(encoding="utf-8").splitlines()
    print("──── 每一次呼叫（從 log 讀）────")
    for i, line in enumerate(lines, 1):
        o = json.loads(line)
        prompt = o["request"]["messages"][0]["content"]
        stage = "plan_or_audit" if prompt.startswith("Design") else ("execute" if prompt.startswith("Write") else "?")
        usage = o["response"].get("usage", {})
        it = (usage.get("iterations") or [usage])[0]
        print("  #" + str(i) + " " + stage.ljust(14) + " 要求 " + o["request"]["model"].ljust(16) + " 實際 " + o["response"]["model"].ljust(16) + " in " + str(it.get("input_tokens")) + " out " + str(it.get("output_tokens")))
    print()
    print("──── fable_scanner monitor ────")
    mon.print_report(mon.analyze(lines))
print()
print("──── 缺口：同一個模型，兩張價目表 ────")
for m in cd.PRICES:
    print("  " + m.ljust(18) + " cost_dashboard " + str(cd.PRICES[m]) + "   monitor " + str(mon.PRICE_PER_M.get(m)))
son = [("8000", "3000"), ("9000", "3200"), ("4000", "1500")]   # 這週 Sonnet 的 3 筆（輸入、輸出 token）
a = sum(int(i) / 1e6 * 2 + int(o) / 1e6 * 10 for i, o in son)
b = sum(int(i) / 1e6 * 3 + int(o) / 1e6 * 15 for i, o in son)
print("  Sonnet 這週 3 筆：優惠價 USD " + format(a, ".4f") + "  vs  monitor 價 USD " + format(b, ".4f"))
today = datetime.date.today()
print("  cost_dashboard 註解寫優惠價只到 2026-08-31；今天 " + str(today) + "，" + ("已過期" if today > datetime.date(2026, 8, 31) else "還有效"))'
   show "$P"; py_run "$P" ;;
6) banner "MCP 連接器稽核，先用四條規則判"
   tip "能用規則判的先用程式判。mcp_audit.py 的 prep 是叫便宜模型算天真風險分數，其實四條規則（權限、驗證、閒置、金鑰位置）就做得到。結果存到 ch04/interactive/mcp-rules.txt。不呼叫模型。"
   P='import json
from pathlib import Path
servers = json.loads(Path("projects/02_mcp_audit/sample_mcp_servers.json").read_text(encoding="utf-8"))
RULES = [
    ("R1 scope 含 admin 或 *", lambda s: any("admin" in x or "*" in x for x in s["scopes"])),
    ("R2 auth 為 none", lambda s: s["auth"] == "none"),
    ("R3 超過 90 天沒用", lambda s: s["last_used_days_ago"] > 90),
    ("R4 金鑰放環境變數", lambda s: s["auth"] == "env_var_key"),
]
rows = []
for s in servers:
    hits = [name for name, rule in RULES if rule(s)]
    rows.append((len(hits), s["name"], hits))
rows.sort(key=lambda r: -r[0])                 # 排序穩定，同分照 JSON 原順序
out = ["分數   連接器                命中規則"]
for score, name, hits in rows:
    hits_text = "、".join(hits) or "（無）"
    out.append("  " + str(score) + "/4  " + name.ljust(20) + " " + hits_text)
text = "\n".join(out)
Path("../ch04/interactive/mcp-rules.txt").write_text(text + "\n", encoding="utf-8")
print(text)
print()
print("規則看得到：權限大小、驗證方式、閒置天數、金鑰放哪。")
print("規則看不到：功能重疊、某個 scope 實際用到哪些工具——這才需要模型判斷。")'
   show "$P"; py_run "$P" ;;
7) banner "跑 MCP 稽核：模型多看出什麼"
   tip "會呼叫模型 3 次：prep 用 Sonnet 整理清單、plan_or_audit 用 Fable 5（effort high）排名與整併、execute 用 Sonnet 寫處置清單，約需 2～4 分鐘。log 寫到 ch04/interactive/calls-02.jsonl，最後並排第 6 步的規則排名。輸出裡的 email 會先遮蔽再顯示與存檔。"
   P='rm -f ../ch04/interactive/calls-02.jsonl ../ch04/interactive/run-02.txt
K143_CLI_LOG=../ch04/interactive/calls-02.jsonl python ../run_with_cli.py projects/02_mcp_audit/mcp_audit.py 2>&1 | sed -E "s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]+/<email 已遮蔽>/g" | tee ../ch04/interactive/run-02.txt
echo
echo "──── 呼叫紀錄 ────"
python -m fable_scanner monitor ../ch04/interactive/calls-02.jsonl
echo
echo "──── 對照：第 6 步純 Python 規則排名 ────"
cat ../ch04/interactive/mcp-rules.txt 2>/dev/null || echo "（找不到規則結果，先跑第 6 步）"'
   show "$P"; sh_run "$P" ;;
8) banner "總結：昂貴規劃，廉價建置"
   tip "貴的模型只花在判斷最密的那段，其他交給便宜模型或純 Python；錢花在哪，要看呼叫紀錄。"
   P='cat <<EOF
  第 4 章總結
    一個迴圈套十個專案：prep → plan_or_audit → execute → verify，換的只是資料
    高階模型只出現在判斷最密的那段（plan_or_audit 用 Fable high、verify 用 Fable low），其餘交給 Sonnet
    一句話測試：沒有分支、沒有判斷的任務交給最便宜的模型，甚至純 Python（成本儀表板的加總、MCP 的四條規則）
    錢花在哪要看呼叫紀錄（K143_CLI_LOG＋monitor），不要相信模型報告裡自己算的金額
    價目表也是程式碼：優惠價過期、兩處價格不一致，成本報表就會默默算錯
    資安題目容易誤觸 cyber 分類器，plan_or_audit 會回報是否轉給備援；真實部署要先接好備援、處理拒答回 None
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch04.sh <步驟 1-8>"; exit 1 ;;
esac
