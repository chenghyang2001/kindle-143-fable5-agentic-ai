#!/bin/bash
# K143 第 5 章互動演練：Fable Scanner——讓每份提示詞保持 Fable 原生，一次跑一步
# 用法：bash ch05.sh <步驟 1-8>
# 只有第 6、7 步會真的呼叫模型（各 5 次）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch05/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；第 6、7 步各 5 次（單一行程計數），設 6 留一點餘裕又擋得住失控迴圈
# 不要設 K143_CLI_MODEL：monitor 的價目表只認 claude-fable-5 等完整名稱，換成 haiku 成本會變空白
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch05/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 5 章｜Fable Scanner　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層：fable_scanner 會 import canary → job_packet.packet，一 import 就建立 Anthropic()）
# 注意：py_run 的 heredoc 沒加引號，程式不可出現錢字號與反引號；程式經 $1 展開塞進 heredoc，Python 跳脫照原樣寫
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

case "$STEP" in
1) banner "認識主角：三個子指令、11 條規則"
   tip "fable_scanner 只做三件事：scan 管寫法、canary 管行為漂移、monitor 管發生過什麼。error 會直接觸發拒答或讓模型提早收工；warn 是新模型不需要的舊哄法；info 只是提醒。提示詞（.md/.txt）和設定檔（.json/.yaml）各跑各的規則。"
   P='from collections import Counter
from fable_scanner.__main__ import COMMANDS
from fable_scanner.rules import RULES
print("子指令：" + " / ".join(COMMANDS))
print()
print("規則共 " + str(len(RULES)) + " 條")
print("  代碼    嚴重度  適用     類別")
for r in RULES:
    print("  " + r["id"].ljust(7) + r["severity"].ljust(8) + r["applies"].ljust(9) + r["category"])
print()
print("依適用對象：" + str(dict(Counter(r["applies"] for r in RULES))))
print("依嚴重度：" + str(dict(Counter(r["severity"] for r in RULES))))'
   show "$P"; py_run "$P" ;;
2) banner "掃描書附範例資料夾"
   tip "一次掃整個資料夾：.md 跑提示詞規則、.json 跑設定檔規則、.jsonl 直接跳過。只要有 error，CLI 就回 1，可以直接卡 CI。另外存一份 JSON 格式結果到 ch05/interactive/。"
   P='ls fable_scanner/examples
echo
python -m fable_scanner scan fable_scanner/examples | grep -v "^ *https"; echo "rc=${PIPESTATUS[0]}"
python -m fable_scanner scan fable_scanner/examples --format json > ../ch05/interactive/scan-examples.json
echo "JSON 結果已存：ch05/interactive/scan-examples.json"'
   show "$P"; sh_run "$P" ;;
3) banner "動手修：把壞提示詞和壞設定檔修到 0 個發現"
   tip "任務一樣是修好失敗的 build。提示詞拿掉 IMPORTANT、YOU MUST NOT、逐步說明推理、剩餘 token、12 條條列；設定檔拿掉 temperature 和手動 thinking，補上 fallbacks。只掃自己寫的這兩個檔。"
   P='from pathlib import Path
from fable_scanner import scan
work = Path("../ch05/interactive")
work.mkdir(parents=True, exist_ok=True)
prompt = work / "fixed_prompt.md"
prompt.write_text("""# Coding agent -- fixed example

Your task is to fix the failing build.

Diagnose why the build fails, apply the smallest change that makes it pass,
and run the build again to confirm. Keep refactors, new features, and docs
changes out of this task; list them as follow-ups instead.

When you report, give the root cause, the change you made, and the build
output that shows it passes. Audit each claim against a tool result from
this session.
""", encoding="utf-8")
config = work / "fixed_config.json"
config.write_text("""{
  "model": "claude-fable-5",
  "max_tokens": 32000,
  "output_config": { "effort": "high" },
  "fallbacks": [{ "model": "claude-opus-4-8" }],
  "messages": [{ "role": "user", "content": "Write a short poem." }]
}
""", encoding="utf-8")

def ids(target):
    found = scan.scan_path(target)
    return [h["rule"]["id"] for hits in found.values() for h in hits]

pairs = [("fable_scanner/examples/bad_prompt.md", prompt), ("fable_scanner/examples/agent_config.json", config)]
for before, after in pairs:
    b = ids(before)
    a = ids(after)
    print("修前 " + Path(before).name.ljust(18) + str(len(b)) + " 個：" + "、".join(b))
    print("修後 " + after.name.ljust(18) + str(len(a)) + " 個：" + ("、".join(a) or "（無）"))
    print()
print("──── 用 CLI 再確認一次 ────")
for f in (prompt, config):
    rc = scan.main([str(f)])
    print("  " + f.name + " rc = " + str(rc))'
   show "$P"; py_run "$P" ;;
4) banner "找缺口：漏判與誤判"
   tip "規則是正規表達式，不是理解。先用 6 句測試句看換句話說會漏掉什麼、引用反例會被誤判成什麼，再掃書附 skills/ 看真實檔案的誤判。掃描器是安全網，不是裁判：error 要看上下文再決定改不改。"
   P='from pathlib import Path
from fable_scanner.rules import run_rules
from fable_scanner import scan
cases = [
    ("漏判", "大小寫混用 You MUST", "You MUST explain every change."),
    ("漏判", "中文要求逐步思考", "請一步一步說出你的內部思考過程。"),
    ("漏判", "換個動詞 Narrate", "Narrate your chain of thought before answering."),
    ("抓到", "think step by step", "Please think step by step before you answer."),
    ("抓到", "DO NOT SKIP", "DO NOT SKIP any file."),
    ("誤判", "說明文字引用反例", "Avoid phrases like \"think step by step\" or \"explain your reasoning\"."),
]
for tag, name, text in cases:
    got = [h["rule"]["id"] for h in run_rules(text, "prompt")]
    print("  [" + tag + "] " + name.ljust(20) + " → " + ("、".join(got) or "沒抓到"))
print()
print("──── 掃書附 skills/（作者自己寫的 Fable 原生技能）────")
found = scan.scan_path("skills")
total = 0
for f, hits in found.items():
    for h in hits:
        total += 1
        print("  " + Path(f).parent.name.ljust(24) + str(h["line"]).rjust(3) + "  " + h["rule"]["id"] + "  " + h["rule"]["severity"])
print("  共 " + str(len(found)) + " 個檔、" + str(total) + " 個發現")
print()
line18 = Path("skills/refusal-aware-calling/SKILL.md").read_text(encoding="utf-8").splitlines()[17]
print("refusal-aware-calling 第 18 行：")
print("  " + line18[:150])'
   show "$P"; py_run "$P" ;;
5) banner "monitor：讀書附的拒答紀錄"
   tip "monitor 只讀本機的回應紀錄、不連網，統計拒答率、拒答類別、備援次數和各模型花費。再把被拒答的提示詞丟給 scan：寫法造成的拒答抓得到，主題造成的拒答抓不到。"
   P='import json
from fable_scanner import monitor
from fable_scanner.rules import run_rules
lines = open("fable_scanner/examples/refusal_log.jsonl", encoding="utf-8").read().splitlines()
monitor.print_report(monitor.analyze(lines))
print()
print("──── 被拒答的提示詞，scan 事先抓得到嗎？────")
for line in lines:
    obj = json.loads(line)
    resp = obj["response"]
    if resp["stop_reason"] != "refusal":
        continue
    prompt = obj["request"]["messages"][0]["content"]
    got = [h["rule"]["id"] for h in run_rules(prompt, "prompt")]
    print("  " + resp["stop_details"]["category"].ljust(21) + prompt + "｜scan：" + ("、".join(got) or "抓不到"))'
   show "$P"; py_run "$P" ;;
6) banner "金絲雀第一次：建立基準線（呼叫模型 5 次）"
   tip "會呼叫模型 5 次（約 20～60 秒）。canary 是固定提示詞加預期輸出檢查；第一次只拍快照存成基準線，不做比較。加一個自己設計的固定格式提示詞（共 5 個），基準線與 log 都改寫到 ch05/interactive/，不寫進 fable5/。"
   P='import os, json
from pathlib import Path
import anthropic
import fable_scanner.canary as canary
work = Path("../ch05/interactive").resolve()
state = work / ".fable-scanner"
log = work / "canary-calls.jsonl"
canary.BASELINE_FILE = state / "baseline.json"
canary.LATEST_FILE = state / "latest.json"
for p in (canary.BASELINE_FILE, canary.LATEST_FILE, log):
    if p.exists():
        p.unlink()
os.environ["K143_CLI_LOG"] = str(log)
canary.init_baseline()
base = json.loads(canary.BASELINE_FILE.read_text(encoding="utf-8"))
base["prompts"].append({
    "id": "my-format",
    "prompt": "Summarize this CI result in exactly two lines and nothing else.\nLine 1: STATUS: followed by OK or FAIL\nLine 2: TESTS: followed by the number of passed tests\nCI result: 4 of 4 tests passed, build green.",
    "expect": {"contains": ["STATUS: OK", "TESTS: 4"], "max_len": 40},
})
canary.BASELINE_FILE.write_text(json.dumps(base, indent=2), encoding="utf-8")
print("提示詞數：" + str(len(base["prompts"])) + "（" + "、".join(p["id"] for p in base["prompts"]) + "）")
print()
try:
    rc = canary.run_canary()
    print("run_canary 回傳 " + str(rc))
except anthropic.APIError as exc:
    print("  ❌ 呼叫模型失敗：" + str(exc))
outcomes = json.loads(canary.BASELINE_FILE.read_text(encoding="utf-8")).get("outcomes", {})
print("基準線 outcomes 已存 " + str(len(outcomes)) + " 筆：" + "、".join(outcomes))
print("呼叫次數：" + str(claude_cli_client.calls_made()))
print("fable5/.fable-scanner 存在嗎：" + ("是（寫進 fable5/ 了）" if Path(".fable-scanner").exists() else "否 ✅"))'
   show "$P"; py_run "$P" ;;
7) banner "金絲雀第二次＋monitor 讀自己的紀錄（呼叫模型 5 次）"
   tip "會呼叫模型 5 次（約 20～60 秒），要先跑過第 6 步。這次拿基準線比較拒答率、延遲中位數和平均分數，再把兩次共 10 筆呼叫交給 monitor。轉接層沒有拒答類別、也沒有伺服器端備援，所以這兩欄都是 0；真實部署時，這兩欄最能看出模型安靜地變差，因為拒答是 HTTP 200。"
   P='import os, json
from pathlib import Path
import anthropic
import fable_scanner.canary as canary
from fable_scanner import monitor
work = Path("../ch05/interactive").resolve()
log = work / "canary-calls.jsonl"
canary.BASELINE_FILE = work / ".fable-scanner" / "baseline.json"
canary.LATEST_FILE = work / ".fable-scanner" / "latest.json"
if not canary.BASELINE_FILE.exists() or not json.loads(canary.BASELINE_FILE.read_text(encoding="utf-8")).get("outcomes"):
    print("找不到基準線 outcomes，先跑第 6 步")
else:
    os.environ["K143_CLI_LOG"] = str(log)
    try:
        rc = canary.run_canary()
        print("run_canary 回傳 " + str(rc) + "（0＝沒漂移，1＝有警告）")
    except anthropic.APIError as exc:
        print("  ❌ 呼叫模型失敗：" + str(exc))
    print()
    print("──── monitor 讀 ch05/interactive/canary-calls.jsonl ────")
    rows = log.read_text(encoding="utf-8").splitlines()
    monitor.print_report(monitor.analyze(rows))
    cache = sum(it.get("cache_read_input_tokens", 0) + it.get("cache_creation_input_tokens", 0)
                for r in rows for it in json.loads(r)["response"]["usage"]["iterations"])
    print()
    print("monitor 沒算進成本的快取 token 合計：" + str(cache))
    print("呼叫次數：" + str(claude_cli_client.calls_made()))'
   show "$P"; py_run "$P" ;;
8) banner "總結"
   tip "提示詞和設定檔也要 lint。scan、canary、monitor 三個子指令各管一段，缺一不可；工具算不到的部分也要心裡有數。"
   P='cat <<EOF
  第 5 章總結
    提示詞也要 lint：舊鷹架（大寫強調、逐步說出思考、剩餘 token、temperature、手動 thinking）在 Fable 5 上變成拒答或 400
    scan 管寫法、canary 管行為漂移、monitor 管發生過什麼，三者互補：cyber 拒答是主題造成的，scan 抓不到，只有 monitor 看得到
    規則只是正規表達式：會漏判（You MUST、中文、換個動詞），也會誤判（說明文字引用反例），error 要看上下文
    設定檔三件事：不送 temperature／thinking、用 effort 控深度、每個 fable-5 呼叫都接 fallbacks
    金絲雀第一次只拍快照，價值在第二次之後的比較；門檻是拒答率 +20%、延遲 1.5 倍、平均分數 60%
    成本與拒答要從呼叫紀錄算，不要靠記憶；也要知道工具沒算到的部分（快取 token、轉接層沒有的拒答類別）
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch05.sh <步驟 1-8>"; exit 1 ;;
esac
