#!/bin/bash
# K143 第 10 章互動演練：Effort 旋鈕就是成本旋鈕——路由表、缺口、攔截請求與真實 token 量測，一次跑一步
# 用法：bash ch10.sh <步驟 1-8>
# 只有第 6 步（3 次）與第 7 步（2 次）會真的呼叫模型：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch10/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；每步是獨立行程、計數會重來，最多一步 3 次，設 6 留餘裕又擋得住失控迴圈
# 刻意不設 K143_CLI_MODEL：monitor 的價目表只認 claude-fable-5 這類完整名稱，換成 haiku 成本會變空白
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch10/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 10 章｜Effort 與成本　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p）
# effort_router.py 一 import 就建立 Anthropic()，所以一定要先 install 再匯入
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

# 第 6、7 步共用的提示詞：一段部署失敗紀錄
# 注意：py_run 的 heredoc 沒加引號，這段程式不可出現錢字號與反引號
# 程式是經 $1 展開塞進 heredoc 的，展開結果不再做反斜線處理，所以 Python 跳脫照原樣寫
SUM_PY='SUMMARY = ("請用三句話摘要這段部署失敗紀錄：\n"
           "10:02 開始部署 api-gateway v2.3.1\n"
           "10:03 健康檢查失敗：環境變數 DATABASE_URL 未設定\n"
           "10:04 自動回滾到 v2.3.0，服務恢復\n"
           "10:20 確認新的 Helm values 檔漏了 DATABASE_URL")
'

case "$STEP" in
1) banner "認識主角：effort_router.py 的 effort_for() 與 run()"
   tip "effort 有五級，不設就是 high。整個機隊「依任務類型挑 effort」的政策就寫在一個 15 行內的 effort_for() 裡。注意第 20 行一 import 就建立 Anthropic()，所以要先裝轉接層，而且不能直接執行 main()（會一次跑 3 個任務）。"
   P='sed -n 1,47p effort/effort_router.py
echo
echo "──── 關鍵行（行號）────"
grep -n "LEVELS =\|client = Anthropic\|def effort_for\|def run\|def main\|output_config\|return \"" effort/effort_router.py
echo
echo "──── 技能版 SKILL.md 的預設建議 ────"
sed -n 10,15p skills/effort-router/SKILL.md'
   show "$P"; sh_run "$P" ;;
2) banner "路由表攤開看：五級各收哪些任務、沒列到的全掉進 high"
   tip "把 12 種常見任務丟進 effort_for() 分組，看 max 有沒有任務用；再試大小寫不同、拼錯字、沒給 kind、審查者 grade——看它們是不是全部默默變成 high。不呼叫模型。"
   P='import effort.effort_router as er
print("五個等級：" + ", ".join(er.LEVELS))
kinds = ["classify", "extract", "format", "summarize", "chat", "route",
         "migrate", "audit", "novel-research", "write-code", "grade", "plan"]
groups = {}
for kind in kinds:
    groups.setdefault(er.effort_for({"kind": kind}), []).append(kind)
print()
print("等級｜收到的任務")
for lvl in er.LEVELS:
    print("  " + lvl.ljust(6) + "｜" + (", ".join(groups.get(lvl, [])) or "（沒有任務）"))
print()
print("缺口實驗（全部不在表上）：")
for label, task in [("大小寫不同 Classify", {"kind": "Classify"}),
                    ("拼錯 sumarize", {"kind": "sumarize"}),
                    ("沒給 kind", {}),
                    ("審查者 grade", {"kind": "grade"})]:
    print("  " + label.ljust(16) + " → " + er.effort_for(task))
print()
print("README 建議審查者跑 low，但這個路由會把 grade 送到 high。")'
   show "$P"; py_run "$P" ;;
3) banner "機隊健檢：linter 抓「沒設 effort」，再數全 repo 寫死了幾個 effort"
   tip "先用第 7 章的 lint() 檢查一個沒設 effort 的請求；再掃 fable5/ 所有 .py，數 effort=... 寫死的次數，看有沒有人真的呼叫 effort_for()。不呼叫模型。"
   P='import re
from collections import Counter
from pathlib import Path
from migration.migration_linter import lint
req = {"model": "claude-fable-5", "fallbacks": [{"model": "claude-opus-4-8"}],
       "messages": [{"role": "user", "content": "hi"}]}
print("──── 一個沒設 effort 的請求丟給 lint() ────")
for field, sev, msg in lint(req):
    print("  " + sev.upper().ljust(5) + " " + field + "：" + msg)
print()
rx = re.compile("effort=.(low|medium|high|xhigh|max).")
counts, where, users = Counter(), {}, []
for p in sorted(Path(".").rglob("*.py")):
    text = p.read_text(encoding="utf-8")
    for lvl in rx.findall(text):
        counts[lvl] += 1
        where.setdefault(lvl, set()).add(p.parts[0])
    if "effort_for" in text and p.name != "effort_router.py":
        users.append(str(p))
print("──── fable5/ 裡寫死 effort=「...」的次數 ────")
for lvl in ("low", "medium", "high", "xhigh", "max"):
    print("  " + lvl.ljust(6) + str(counts[lvl]).rjust(3) + " 次｜" + ", ".join(sorted(where.get(lvl, []))))
print("  合計 " + str(sum(counts.values())) + " 處")
print()
print("effort_router.py 以外有呼叫 effort_for 的檔案：" + (", ".join(users) or "0 個"))'
   show "$P"; py_run "$P" ;;
4) banner "攔截 run() 的請求本體：output_config.effort 怎麼傳、轉接層又怎麼轉"
   tip "把 er.client 換成只會記錄的假 client（不呼叫模型），看 run() 送出的 output_config、betas、fallbacks；再用轉接層的 _build_command() 看 effort 變成 claude -p --effort，以及拼錯的 extreme 會不會被默默丟掉。"
   P='import copy
from types import SimpleNamespace as NS
import claude_cli_client as cc
import effort.effort_router as er
sent = []
def fake_create(**kw):
    sent.append(copy.deepcopy(kw))
    return NS(usage=NS(output_tokens=42))       # 假裝回 42 個輸出 token
er.client = NS(beta=NS(messages=NS(create=fake_create)))   # run() 讀模組層 client，換掉就生效
r = er.run({"kind": "audit", "prompt": "替部署代理做威脅評估"})
print("run() 回傳：" + str(r))
print("送出的欄位：" + ", ".join(sent[0]))
print("  output_config = " + str(sent[0]["output_config"]))
print("  betas         = " + str(sent[0]["betas"]))
print("  fallbacks     = " + str(sent[0]["fallbacks"]))
print("  max_tokens    = " + str(sent[0]["max_tokens"]))
print()
print("──── 轉接層把 effort 轉成 CLI 參數 ────")
for lvl in ("low", "xhigh", "extreme"):
    cmd = cc._build_command("claude", er.FABLE, "sys.txt", lvl, False)
    if "--effort" in cmd:
        i = cmd.index("--effort")
        tail = str(cmd[i:i + 2])
    else:
        tail = "（沒有 --effort，CLI 用自己的預設）"
    print("  effort=" + lvl.ljust(8) + " → " + tail)
print()
print("轉接層會忽略：betas、fallbacks、max_tokens（見 _Messages.create 的 **ignored）")'
   show "$P"; py_run "$P" ;;
5) banner "動手改：複製 effort_for() 成自己的版本，加入本書演練會遇到的任務"
   tip "寫一份 my_router.py 到 ch10/interactive/：先把 kind 轉小寫去空白（補第 2 步的缺口），加入 grade、lint-explain、write-report、threat-model，每種附一行理由，最後跑 7 個 assert。重跑會直接覆蓋。不呼叫模型。"
   P='cat > ../ch10/interactive/my_router.py <<EOF
"""第 10 章演練：我的 effort 路由政策（由書附 effort_for 複製改寫）"""
POLICY = {
    # 任務類型: (effort, 為什麼)
    "classify":       ("low",    "只要選一個標籤，多想不會更準"),
    "extract":        ("low",    "格式擷取，答案就在輸入裡"),
    "format":         ("low",    "純轉換，不需要推理"),
    "grade":          ("low",    "審查者只核對產出和證據，README 建議 low"),
    "summarize":      ("medium", "要挑重點，但不需要長推論"),
    "lint-explain":   ("medium", "把 linter 的規則說成白話，規則已經定好"),
    "chat":           ("medium", "一般問答，使用者在等"),
    "write-report":   ("high",   "演練報告要組織多步結果，用 API 預設"),
    "migrate":        ("xhigh",  "一次到位的遷移，錯了代價高"),
    "audit":          ("xhigh",  "稽核要找出沒想到的路徑"),
    "threat-model":   ("xhigh",  "攻擊面要窮舉，值得付最高價"),
}
DEFAULT = "high"

def my_effort_for(task):
    """先把 kind 轉小寫去空白，再查表；查不到用 high"""
    kind = str(task.get("kind") or "").strip().lower()
    return POLICY.get(kind, (DEFAULT, "表上沒有，落到預設"))[0]

if __name__ == "__main__":
    for kind, (lvl, why) in POLICY.items():
        print(kind.ljust(14) + lvl.ljust(7) + why)
    assert my_effort_for({"kind": "grade"}) == "low"
    assert my_effort_for({"kind": "lint-explain"}) == "medium"
    assert my_effort_for({"kind": "write-report"}) == "high"
    assert my_effort_for({"kind": "threat-model"}) == "xhigh"
    assert my_effort_for({"kind": "Classify "}) == "low"     # 第 2 步的大小寫缺口已補
    assert my_effort_for({}) == "high"
    assert my_effort_for({"kind": "sumarize"}) == "high"     # 拼錯仍落到預設：政策只能防呆，不能猜
    print("全部 7 個 assert 通過")
EOF
python ../ch10/interactive/my_router.py | tee ../ch10/interactive/my-router.txt
echo
echo "已寫入 ../ch10/interactive/my_router.py 與 my-router.txt"'
   show "$P"; sh_run "$P" ;;
6) banner "真的跑路由：classify／summarize／audit 各一次（呼叫模型 3 次）"
   tip "會呼叫模型 3 次。用書附 er.run()（不是 main()）跑三種任務，讓路由自動挑 low／medium／xhigh，記下真實的 output_tokens；log 寫成 monitor 讀得懂的 JSONL 到 ch10/interactive/calls-run.jsonl，第 7 步拿來算錢。約需 1～4 分鐘。"
   P='import os
from pathlib import Path
import anthropic
import claude_cli_client
import effort.effort_router as er
work = Path("../ch10/interactive").resolve()
log = work / "calls-run.jsonl"
if log.exists():
    log.unlink()                                  # 清掉舊 log，重跑才可重現
os.environ["K143_CLI_LOG"] = str(log)             # 轉接層每次呼叫才讀，設在這裡就生效
tasks = [
    {"kind": "classify", "prompt": "這張工單是 bug 還是 feature？只回一個英文字。工單：存檔時 App 當掉。"},
    {"kind": "summarize", "prompt": SUMMARY},
    {"kind": "audit", "prompt": "替一個能讀工單、又能自己部署的代理做簡短威脅評估，用繁體中文，10 行以內。"},
]
rows = []
for task in tasks:
    try:
        r = er.run(task)
        rows.append(r["kind"].ljust(10) + " effort=" + r["effort"].ljust(6) + " out=" + str(r["output_tokens"]) + " tok")
    except anthropic.APIError as exc:
        rows.append(task["kind"].ljust(10) + " ❌ 呼叫失敗：" + str(exc)[:120])
    print(rows[-1])
rows.append("claude -p 呼叫次數：" + str(claude_cli_client.calls_made()))
out = work / "effort-results.txt"
out.write_text("\n".join(rows) + "\n", encoding="utf-8")
print(rows[-1])
print()
print("已寫入 " + str(out) + " 與 " + str(log))'
   show "$SUM_PY
$P"; py_run "$SUM_PY
$P" ;;
7) banner "控制變因實驗：同一段 summarize 只換 effort（呼叫模型 2 次）"
   tip "會呼叫模型 2 次。固定提示詞與模型，只把 effort 從 low 換成 xhigh，量真實 output_tokens 的倍數，用 monitor 的價目（輸出每百萬 50 美元）算成本差，再把第 6、7 步的 log 合起來出報表。effort 不是硬上限，差異小或反轉都要照實看。"
   P='import os
from pathlib import Path
import anthropic
import claude_cli_client
from fable_scanner.monitor import PRICE_PER_M, analyze, print_report
work = Path("../ch10/interactive").resolve()
log = work / "calls-compare.jsonl"
if log.exists():
    log.unlink()
os.environ["K143_CLI_LOG"] = str(log)
client = anthropic.Anthropic()                    # 已 install()，拿到的是轉接層
OUT_PRICE = PRICE_PER_M["claude-fable-5"][1]      # 每百萬輸出 token 的美元
tok = {}
for lvl in ("low", "xhigh"):
    try:
        m = client.messages.create(model="claude-fable-5", max_tokens=2048,
                                   output_config={"effort": lvl},
                                   messages=[{"role": "user", "content": SUMMARY}])
        tok[lvl] = m.usage.output_tokens
        print("effort=" + lvl.ljust(6) + " out=" + str(tok[lvl]) + " tok｜回答前 60 字：" + m.content[0].text.strip().replace("\n", " ")[:60])
    except anthropic.APIError as exc:
        print("effort=" + lvl + " ❌ 呼叫失敗：" + str(exc)[:120])
rows = []
if len(tok) == 2 and tok["low"]:
    c_low = tok["low"] * OUT_PRICE / 1e6
    c_x = tok["xhigh"] * OUT_PRICE / 1e6
    rows += ["【本次樣本】xhigh / low = " + format(tok["xhigh"] / tok["low"], ".2f") + " 倍",
             "輸出成本：low " + format(c_low, ".6f") + " 美元、xhigh " + format(c_x, ".6f") + " 美元，差 " + format(c_x - c_low, ".6f") + " 美元",
             "放大到一天 1 萬次 summarize：差 " + format((c_x - c_low) * 10000, ".2f") + " 美元"]
rows += ["claude -p 呼叫次數：" + str(claude_cli_client.calls_made()),
         "注意：effort 不是硬上限，差異可能很小甚至反轉；轉接層用 claude -p --effort 傳遞，結果可能和直接打 API 不同"]
(work / "effort-compare.txt").write_text("\n".join(rows) + "\n", encoding="utf-8")
print()
print("\n".join(rows))
print()
print("──── monitor：第 6、7 步合計成本 ────")
lines = []
for name in ("calls-run.jsonl", "calls-compare.jsonl"):
    p = work / name
    if p.exists():
        lines += p.read_text(encoding="utf-8").splitlines()
print_report(analyze(lines))'
   show "$SUM_PY
$P"; py_run "$SUM_PY
$P" ;;
8) banner "總結：effort 是機隊的成本政策"
   tip "一個函式、一處修改，再用真實的 token 數去調整——這就是把 effort 當成本旋鈕的做法。"
   P='cat <<EOF
  第 10 章總結
    effort 有五級 low／medium／high／xhigh／max；不設就是 high——沒設 effort 的機隊等於全跑 high
    effort 影響所有輸出 token：文字、工具呼叫參數、思考；調低不只回答變短，工具呼叫也變少
    它是行為訊號、不是硬上限：low 對 xhigh 的差距要用真實 usage 量，不能用猜的
    成本政策寫成一個函式（effort_for）就是一處修改；但書附 repo 自己有 23 處寫死 effort，沒有人呼叫它
    路由表要防呆：大小寫、拼錯、沒給 kind 都會默默落到 high；審查者 low、執行 medium、規劃與稽核 xhigh 是常見起點
    轉接層用 claude -p --effort 傳遞、忽略 betas／fallbacks／max_tokens，拼錯的 effort 會被默默丟掉——數字可能和直接打 API 不同
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch10.sh <步驟 1-8>"; exit 1 ;;
esac
