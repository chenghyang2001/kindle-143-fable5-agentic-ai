#!/bin/bash
# K143 第 18 章互動演練：治理代理部署——CISO 控制地圖與 10 項上線硬閘門，一次跑一步
# 用法：bash ch18.sh <步驟 1-8>
# 只有第 7 步會真的呼叫模型（3 次：ship_audit 的 prep／plan_or_audit／execute）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch18/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；第 7 步 3 次，設 6 留一點餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch18/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 18 章｜CISO 控制地圖　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p）
# job_packet/packet.py、fable_scanner 一 import 就會建立 Anthropic()，所以連離線步驟也一律走 py_run
# 注意：P 用單引號包住，程式裡不可有單引號；py_run 的 heredoc 沒加引號，py_run 的程式不可出現錢字號與反引號
# 第 5、7 步改用 sh_run 搭配有引號的 heredoc（<<"EOF"），裡面才可以有錢字號
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

case "$STEP" in
1) banner "認識主角：projects/07 的客服代理與上線稽核流程"
   tip "這次要放行的是一個能查單、退款、轉人工的客服代理，40 題評測失敗 4 題。ship_audit.py 用 3 次模型呼叫做上線稽核：便宜模型整理、Fable 稽核、便宜模型提修法。這一步只看檔案，不呼叫模型。"
   P='echo "──── ship_audit.py 說明（第 1～17 行）────"
sed -n 1,17p projects/07_ship_readiness/ship_audit.py
echo
echo "──── 三次模型呼叫在哪裡 ────"
grep -n -E "prep\(|plan_or_audit\(|execute\(" projects/07_ship_readiness/ship_audit.py
grep -n -E "^(FABLE|CHEAP) =" job_packet/packet.py
echo
echo "──── sample_agent/system_prompt.md ────"
cat projects/07_ship_readiness/sample_agent/system_prompt.md
echo
echo "──── sample_agent/tools.json ────"
cat projects/07_ship_readiness/sample_agent/tools.json
echo
echo "──── sample_agent/eval_results.json ────"
cat projects/07_ship_readiness/sample_agent/eval_results.json'
   show "$P"; sh_run "$P" ;;
2) banner "先離線找缺口：掃描器 0 個 finding，評測卻有 4 題失敗"
   tip "fable_scanner 只抓提示詞與設定的寫法問題，抓不到退款工具沒有速率限制、沒有金額上限這類行為缺口。掃描乾淨不等於可以上線，這些要靠閘門和稽核。不呼叫模型。"
   P='import json
from pathlib import Path
from fable_scanner.scan import scan_path
agent = Path("projects/07_ship_readiness/sample_agent")
res = scan_path(agent)
total = sum(len(v) for v in res.values())
print("fable_scanner.scan_path(sample_agent/)：" + str(total) + " 個 finding" + ("（提示詞與設定寫法都沒問題）" if total == 0 else ""))
print()
tools = json.loads((agent / "tools.json").read_text(encoding="utf-8"))
print("工具權限盤點：")
for t in tools:
    lim = t["rate_limit"]
    print("  " + t["name"].ljust(18) + "參數=" + ",".join(t["params"]).ljust(22) + "rate_limit=" + str(lim) + ("  ⚠️ 沒有速率限制" if lim is None else ""))
print("  issue_refund 的 amount_usd 沒有上限欄位：50 美元免審只寫在提示詞裡，工具層不擋")
print()
ev = json.loads((agent / "eval_results.json").read_text(encoding="utf-8"))
print("評測：" + str(ev["passed"]) + " / " + str(ev["total_cases"]) + " 通過，失敗 " + str(len(ev["failed_cases"])) + " 題")
for c in ev["failed_cases"]:
    print("  ❌ " + c["case"])
    print("       預期：" + c["expected"] + "｜實際：" + c["actual"])
print()
print("結論：掃描器看的是「怎麼寫」，看不到「工具能做什麼」——上線要另外用閘門判定。")'
   show "$P"; py_run "$P" ;;
3) banner "產生證據：migration_linter 和 scope_gate 跑在本次部署上"
   tip "閘門看的是證據，證據要由工具產生。替客服代理寫一份 Fable 請求跑 migration_linter，再用 scope_gate 檢查拒答紀錄與備援路徑，結果存到 ch18/interactive/evidence/。各做一個對照：拿掉 fallbacks、把模型換成 Mythos。不呼叫模型。"
   P='import json
from pathlib import Path
from migration.migration_linter import lint
from mythos_scope.scope_gate import lint_scope
work = Path("../ch18/interactive").resolve()
ev = work / "evidence"
ev.mkdir(parents=True, exist_ok=True)

def fmt(findings):
    if not findings:
        return ["  clean：0 個 finding"]
    return ["  " + sev.ljust(5) + " " + field + "｜" + msg[:60] for field, sev, msg in findings]

req = {"model": "claude-fable-5", "max_tokens": 4000,
       "output_config": {"effort": "medium"},
       "fallbacks": [{"model": "claude-opus-4-8"}],
       "messages": [{"role": "user", "content": "我的訂單 A-123 想退款"}]}
(work / "agent_request.json").write_text(json.dumps(req, ensure_ascii=False, indent=2), encoding="utf-8")
lines = ["# migration_linter.lint(ch18/interactive/agent_request.json)",
         "model=" + req["model"] + "  effort=" + req["output_config"]["effort"] + "  fallbacks=" + req["fallbacks"][0]["model"]] + fmt(lint(req))
(ev / "lint.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
print("對照：同一份請求拿掉 fallbacks 再 lint")
print("\n".join(fmt(lint({k: v for k, v in req.items() if k != "fallbacks"}))))
print()

scope = json.loads(Path("mythos_scope/sample_fable_scope.json").read_text(encoding="utf-8"))
lines = ["# scope_gate.lint_scope(mythos_scope/sample_fable_scope.json)",
         "model=" + scope["model"] + "  refusal_logging=" + str(scope["refusal_logging"]) + "  fallbacks=" + scope["fallbacks"][0]["model"]] + fmt(lint_scope(scope))
(ev / "scope.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
mythos = dict(scope, model="claude-mythos-5")
f = lint_scope(mythos)
print("對照：同一份封包把 model 換成 claude-mythos-5 → " + str(len(f)) + " 個 finding，error " + str(sum(1 for x in f if x[1] == "error")) + " 個")
print("\n".join(fmt(f)))
print()
for p in sorted(ev.glob("*.txt")):
    print("已寫入證據：" + p.relative_to(work.parents[1]).as_posix() + "（" + str(p.stat().st_size) + " bytes）")'
   show "$P"; py_run "$P" ;;
4) banner "寫部署清單：值照團隊宣稱填，證據只填真的存在的檔"
   tip "10 個閘門的值照團隊宣稱填 true（Mythos 兩項因為是 Fable 部署，標 not_applicable）；證據逐一到前面各章的產出裡找，不存在或是空檔就老實填 none。零資料保留沒有工具能產生證據，一定是 none。不呼叫模型。"
   P='import json
from pathlib import Path
base = Path("..").resolve()
work = Path("../ch18/interactive").resolve()
CANDIDATES = [
    ("model_variant_documented", ["ch18/interactive/evidence/lint.txt", "ch07/lint-after.txt"]),
    ("retention_resolved", []),
    ("fable_refusal_path_wired", ["ch18/interactive/evidence/scope.txt"]),
    ("fallback_gap_handled", ["ch15/fallback-gaps.md"]),
    ("mythos_scope_packet_required", None),
    ("mythos_artifact_controls_on", None),
    ("memory_gate_on", ["ch03/scan-output.txt"]),
    ("mcp_least_privilege", ["ch14/least-privilege.txt"]),
    ("injection_boundary_set", ["ch14/scan.txt", "ch13/live-output.txt"]),
    ("verifier_running", ["ch02/triage-output.txt"]),
]
gates = {}
for name, cands in CANDIDATES:
    if cands is None:
        gates[name] = {"value": "not_applicable", "evidence": "none"}
        print(name.ljust(30) + "→ not_applicable（Fable 部署）")
        continue
    chosen = "none"
    notes = []
    for c in cands:
        p = base / c
        size = p.stat().st_size if p.is_file() else -1
        notes.append(c + "（" + ("不存在" if size < 0 else str(size) + " bytes") + "）")
        if size > 0 and chosen == "none":
            chosen = c
    gates[name] = {"value": True, "evidence": chosen}
    print(name.ljust(30) + "→ 宣稱 true｜證據：" + chosen)
    print("    候選：" + ("；".join(notes) if notes else "沒有任何工具能產生這項證據"))
dep = {"deployment": "projects/07 客服代理上線", "model": "claude-fable-5",
       "fallback_model": "claude-opus-4-8", "gates": gates}
out = work / "deployment.json"
out.write_text(json.dumps(dep, ensure_ascii=False, indent=2), encoding="utf-8")
print()
print("宣稱 true 但證據是 none 的閘門：" + str(sum(1 for x in gates.values() if x["value"] is True and x["evidence"] == "none")) + " 個")
print("已寫入 " + str(out))'
   show "$P"; py_run "$P" ;;
5) banner "10 項硬閘門：任何一項 FALSE 就是 NO-GO"
   tip "上線決策不打分數，改用不靠模型的布林閘門：值必須是 true，而且證據檔真的存在、不是空的；Mythos 兩項只有 model 是 claude-fable-5 時才准標 not_applicable。寫出 go_no_go.py 後跑一次，exit code 0 是 GO、1 是 NO-GO。不呼叫模型。"
   P='cat > ../ch18/interactive/go_no_go.py <<"EOF"
"""K143 ch18 互動演練：10 項上線硬閘門（不呼叫模型）。
值必須是 true，而且 evidence 指向 practice/ 底下真的存在且非空的檔案，才算 PASS。"""
import json
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]   # practice/
FABLE = "claude-fable-5"
MYTHOS_ONLY = {"mythos_scope_packet_required", "mythos_artifact_controls_on"}
GATES = [
    ("model_variant_documented", "成本", "migration_linter（ch07）"),
    ("retention_resolved", "資料", "人工簽核零資料保留（無工具）"),
    ("fable_refusal_path_wired", "可用性", "refusal_stack／scope_gate fallbacks（ch01、ch06）"),
    ("fallback_gap_handled", "可用性", "second_pass 補備援盲區（ch15）"),
    ("mythos_scope_packet_required", "保證", "scope_gate（ch06）"),
    ("mythos_artifact_controls_on", "保證", "scope_gate artifact_policy（ch06）"),
    ("memory_gate_on", "資料", "startup_scan 開機檢疫（ch03）"),
    ("mcp_least_privilege", "完整性", "least_privilege／mcp_audit（ch14）"),
    ("injection_boundary_set", "完整性", "工具描述掃描、fence（ch13、ch14）"),
    ("verifier_running", "保證", "驗證子代理 job_packet.verify（ch02）"),
]


def judge(dep, base=BASE):
    model = dep.get("model")
    gates = dep.get("gates", {})
    rows = []
    for name, domain, tool in GATES:
        item = gates.get(name, {})
        value = item.get("value")
        ev = str(item.get("evidence") or "none")
        if value == "not_applicable":
            if name in MYTHOS_ONLY and model == FABLE:
                rows.append((name, domain, "N/A", "Fable 部署，不適用 Mythos"))
            else:
                rows.append((name, domain, "FALSE", "只有 Mythos 兩項、且 model 是 claude-fable-5 才能標 not_applicable"))
            continue
        path = base / ev
        if value is not True:
            rows.append((name, domain, "FALSE", "值不是 true：" + repr(value)))
        elif ev == "none":
            rows.append((name, domain, "FALSE", "宣稱 true，但證據是 none"))
        elif not path.is_file():
            rows.append((name, domain, "FALSE", "證據檔不存在：" + ev))
        elif path.stat().st_size == 0:
            rows.append((name, domain, "FALSE", "證據檔是空的：" + ev))
        else:
            rows.append((name, domain, "PASS", ev))
    return rows


def verdict(rows):
    return "GO" if all(r[2] in ("PASS", "N/A") for r in rows) else "NO-GO"


def main(path):
    dep = json.loads(Path(path).read_text(encoding="utf-8"))
    rows = judge(dep)
    print("部署：" + str(dep.get("deployment")) + "｜model=" + str(dep.get("model")))
    print(" #  閘門                           領域    結果   說明")
    for i, (name, domain, status, note) in enumerate(rows, 1):
        print(f"{i:>2}  {name:<30} {domain:<4} {status:<5}  {note}")
    n_pass = sum(1 for r in rows if r[2] == "PASS")
    n_na = sum(1 for r in rows if r[2] == "N/A")
    n_false = sum(1 for r in rows if r[2] == "FALSE")
    print("PASS " + str(n_pass) + "｜N/A " + str(n_na) + "｜FALSE " + str(n_false))
    result = verdict(rows)
    print("最終判定：" + result)
    return 0 if result == "GO" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).with_name("deployment.json"))))
EOF
echo "已寫入 ../ch18/interactive/go_no_go.py（$(wc -l < ../ch18/interactive/go_no_go.py) 行）"
echo
python ../ch18/interactive/go_no_go.py > ../ch18/interactive/gate-result.txt
code=$?
cat ../ch18/interactive/gate-result.txt
echo
echo "exit code = $code（0＝GO、1＝NO-GO），結果已存 ../ch18/interactive/gate-result.txt"'
   show "$P"; sh_run "$P" ;;
6) banner "攻擊自己的閘門：宣稱、缺檔、空檔、亂標 N/A、無關證據"
   tip "確認 go_no_go.py 真的有查證據，不是只看 true／false。再找它的盲區：指向一個存在、非空但跟本部署無關的檔（例如 README.md），它照樣放行。只寫入 evidence/empty.txt，不改 deployment.json。不呼叫模型。"
   P='import json, sys
from pathlib import Path
sys.path.insert(0, str(Path("../ch18/interactive").resolve()))
import go_no_go as g
work = Path("../ch18/interactive").resolve()
(work / "evidence" / "empty.txt").write_text("", encoding="utf-8")
LINT = "ch18/interactive/evidence/lint.txt"

def one(name, value, evidence, model):
    dep = {"model": model, "gates": {name: {"value": value, "evidence": evidence}}}
    return [r for r in g.judge(dep) if r[0] == name][0]

cases = [
    ("宣稱 true、證據 none", "retention_resolved", True, "none", "claude-fable-5"),
    ("證據指向不存在的檔", "retention_resolved", True, "ch18/interactive/evidence/dpa-signed.pdf", "claude-fable-5"),
    ("證據是空檔", "retention_resolved", True, "ch18/interactive/evidence/empty.txt", "claude-fable-5"),
    ("值寫成字串 true", "verifier_running", "true", LINT, "claude-fable-5"),
    ("Fable 部署標 Mythos 項 N/A", "mythos_scope_packet_required", "not_applicable", "none", "claude-fable-5"),
    ("Mythos 部署也標 N/A", "mythos_scope_packet_required", "not_applicable", "none", "claude-mythos-5"),
    ("非 Mythos 項標 N/A", "memory_gate_on", "not_applicable", "none", "claude-fable-5"),
    ("⚠️ 指向無關但非空的 README.md", "retention_resolved", True, "fable5/README.md", "claude-fable-5"),
]
for label, name, value, ev, model in cases:
    _, _, status, note = one(name, value, ev, model)
    print("  " + label.ljust(26) + "→ " + status.ljust(5) + " " + note[:60])
print()
dep = json.loads((work / "deployment.json").read_text(encoding="utf-8"))
fake = json.loads(json.dumps(dep))
for item in fake["gates"].values():
    if item["value"] is True:
        item["evidence"] = LINT
rows = g.judge(fake)
print("把 8 項證據全填同一個 lint.txt：" + g.verdict(rows) + "（PASS " + str(sum(1 for r in rows if r[2] == "PASS")) + " 項）")
print("結論：閘門擋得住「沒證據」，擋不住「拿錯證據」——證據內容是否屬於本部署，要由簽核的人看。")'
   show "$P"; py_run "$P" ;;
7) banner "模型稽核＋CISO 控制地圖（呼叫模型 3 次）"
   tip "會呼叫模型 3 次：ship_audit.py 的 prep、plan_or_audit（Fable xhigh）、execute，約 1～3 分鐘，log 寫到 ch18/interactive/calls.jsonl。接著離線把稽核點名的問題對回閘門；第 5 步 PASS 卻被點名，就要回頭確認證據是否屬於本部署（關鍵字比對很粗，只當提醒）。最後寫成 ciso-map.md，只列還缺的證據，不去補。"
   P='rm -f ../ch18/interactive/calls.jsonl
K143_CLI_LOG=../ch18/interactive/calls.jsonl K143_CLI_TIMEOUT=300 python ../run_with_cli.py projects/07_ship_readiness/ship_audit.py 2>&1 | tee ../ch18/interactive/ship-audit.txt
echo
echo "呼叫次數：$(wc -l < ../ch18/interactive/calls.jsonl 2>/dev/null || echo 0)"
echo
python - <<"EOF"
import json, re, sys
from pathlib import Path
sys.path.insert(0, "../ch18/interactive")
import go_no_go as g
work = Path("../ch18/interactive")
text = (work / "ship-audit.txt").read_text(encoding="utf-8")
text = text.split("=== Go/no-go audit ===", 1)[-1]  # 只看稽核段：前面的 Behavior contract summary 會重述失敗案例，整份比對會誤判「有提到」
dep = json.loads((work / "deployment.json").read_text(encoding="utf-8"))
rows = g.judge(dep)
status = {r[0]: r[2] for r in rows}
MAP = [
    ("退款工具沒有速率限制", r"rate[ -]?limit", "mcp_least_privilege"),
    ("退款超過 50 美元未轉人工", r"\$500|\$50\b|threshold|approval", "mcp_least_privilege"),
    ("不存在的訂單也能退款", r"null|does not exist|nonexist|validat", "mcp_least_privilege"),
    ("客戶訊息可注入指令", r"inject", "injection_boundary_set"),
    ("洩漏內部毛利", r"margin", "injection_boundary_set"),
    ("紀錄／稽核軌跡缺口", r"logging|audit trail|\blogs?\b", "verifier_running"),
]
lines = ["# ch18 CISO 控制地圖（互動演練產出）", "", "## 五大領域 × 閘門 × 工具", "",
         "| 領域 | 閘門 | 對應工具 | 本次結果 |", "|---|---|---|---|"]
for name, domain, tool in sorted(g.GATES, key=lambda x: x[1]):
    lines.append(f"| {domain} | {name} | {tool} | {status[name]} |")
lines += ["", "## 模型稽核發現 → 閘門", "",
          "| 發現 | 稽核有提到 | 會讓它變 FALSE 的閘門 | 第 5 步結果 |", "|---|---|---|---|"]
print("稽核發現".ljust(20) + "有提到  閘門                       第 5 步")
contradicted = set()
for label, rx, gate in MAP:
    hit = bool(re.search(rx, text, re.IGNORECASE))
    yn = "是" if hit else "否"
    st = status[gate]
    flag = ""
    if hit and st == "PASS":
        contradicted.add(gate)
        flag = "  ⚠️ PASS 卻被稽核點名：要回頭確認證據是否屬於本部署"
    print(label.ljust(20) + yn.ljust(6) + gate.ljust(27) + st + flag)
    lines.append(f"| {label} | {yn} | {gate} | {st} |")
missing = [r[0] for r in rows if r[2] == "FALSE"] + sorted(contradicted)
lines += ["", "## 要變成 GO 還缺的證據（只列，不補）", ""]
lines += [f"- {m}：需要針對 projects/07 客服代理本身的證據" for m in missing]
(work / "ciso-map.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print()
print("要 GO 還缺：" + "、".join(missing))
print("已寫入 ../ch18/interactive/ciso-map.md")
EOF'
   show "$P"; sh_run "$P" ;;
8) banner "總結：上線看證據，不看宣稱"
   tip "上線決策用布林閘門取代分數，每一項都要綁定證據；閘門有盲區，最後還是要人審。演練得到 NO-GO 是正常結果。"
   P='cat <<EOF
  第 18 章總結
    上線決策用 10 個布林閘門，不打成熟度分數：任何一項 FALSE 就是 NO-GO（第 5 步）
    閘門看證據不看宣稱：值是 true 還要證據檔真的存在、非空；Mythos 兩項只有 Fable 部署才能標 N/A（第 5、6 步）
    閘門擋得住「沒證據」，擋不住「拿錯證據」：README 也能讓它 PASS，證據是否屬於本部署要人審（第 6、7 步）
    全書工具在這裡匯流：migration_linter、scope_gate、startup_scan、工具描述掃描、second_pass、驗證子代理各自是一個閘門的證據來源
    零資料保留沒有工具能補，要在架構簽核前確認；降到 Opus 備援時 MCP 權限不會自動縮小，最小權限要做在工具層（呼應第 2 步的工具權限盤點）
    演練得到 NO-GO 是正常的——重點是 ciso-map.md 列得出還缺哪些證據
EOF'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch18.sh <步驟 1-8>"; exit 1 ;;
esac
