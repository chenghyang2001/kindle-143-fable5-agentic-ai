#!/bin/bash
# K143 第 6 章互動演練：11 個 Fable／Mythos 原生代理技能——技能地圖、掃描技能、範圍圍欄 A/B、Mythos 範圍閘門，一次跑一步
# 用法：bash ch06.sh <步驟 1-8>
# 只有第 6 步會真的呼叫模型（2 次）：走 claude -p（Max 訂閱），不設 ANTHROPIC_API_KEY
# 所有產出寫到 ch06/interactive/，fable5/ 一個檔都不改、也不寫入
set -u
# 轉接層每次呼叫才讀這個上限；第 6 步 A、B 兩版各 1 次，設 6 留一點餘裕又擋得住失控迴圈
export K143_CLI_MAX_CALLS=6
STEP="${1:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE="$HERE/.."
LAB="$PRACTICE/fable5"
WORK="$PRACTICE/ch06/interactive"   # 動手改的檔案放這裡，不碰 fable5/
mkdir -p "$WORK"
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'

banner() { clear; printf '%s╔══════════════════════════════════════════════════════╗%s\n' "$C" "$N"; printf '%s  K143 第 6 章｜代理技能庫　第 %s / 8 步%s\n' "$B" "$STEP" "$N"; printf '%s  %s%s\n' "$B" "$1" "$N"; printf '%s╚══════════════════════════════════════════════════════╝%s\n\n' "$C" "$N"; }
tip() { printf '%s💡 %s%s\n\n' "$Y" "$1" "$N"; }
show() { printf '%s▶ 要執行的指令：%s\n' "$G" "$N"; printf '%s' "$1" | sed "s/^/${G}  │ ${N}/"; printf '\n%s▶ 執行結果：%s\n' "$G" "$N"; }
done_step() { printf '\n%s👉 第 %s 步完成%s\n' "$C" "$STEP" "$N"; }
# 執行 shell 指令（在 fable5/ 目錄）
sh_run() { (cd "$LAB" && PYTHONUTF8=1 bash -c "$1"); done_step; }
# 執行 Python（先裝轉接層，讓 import anthropic 改走 claude -p）
# 注意：heredoc 沒加引號，內嵌 Python 不可出現錢字號與反引號（三個反引號用 chr(96) * 3）
py_run() { (cd "$LAB" && PYTHONUTF8=1 PYTHONPATH=. python - <<PY
import sys; sys.path.insert(0, ".."); import claude_cli_client; claude_cli_client.install()
$1
PY
); done_step; }

case "$STEP" in
1) banner "認識技能庫：11 個技能、任務型與常駐型"
   tip "對話裡的叮嚀會隨上下文淡掉，作者把規則封裝成 SKILL.md。先看 README 總表：只有 3 個任務型會自動觸發，其餘常駐型要明確呼叫或貼進系統提示詞／CLAUDE.md。"
   P='cat -n skills/README.md
echo
echo "──── skills/ 底下的技能資料夾 ────"
ls -d skills/*/ | sed "s#skills/##; s#/##"
echo "資料夾數量：$(ls -d skills/*/ | wc -l)"'
   show "$P"; sh_run "$P" ;;
2) banner "畫出技能地圖：自動觸發 vs 貼進 CLAUDE.md"
   tip "用程式真的讀 11 份 SKILL.md 的 frontmatter，分出任務型／常駐型、建議放哪裡、對應前面章節哪個範例；再核對 README、plugin.json、marketplace.json 寫的技能數和實際資料夾數是否一致。地圖寫到 ch06/interactive/skill-map.md。"
   P='import json, re
from pathlib import Path
work = Path("../ch06/interactive").resolve()
work.mkdir(parents=True, exist_ok=True)
TASK = {"effort-router", "verifier-subagent", "lesson-memory"}   # README 第 40 行點名的任務型
RELATED = {
    "effort-router": "effort/effort_router.py",
    "refusal-aware-calling": "refusal/refusal_stack.py",
    "lesson-memory": "memory/memory_tool_handler.py",
    "verifier-subagent": "agentic_soc/triage_loop.py",
    "mythos-scope-gate": "mythos_scope/scope_gate.py",
    "scope-fence": "projects/04_refactor_legacy/sample_target.py",
}
def front(text):
    meta = {}
    for line in text.split("---")[1].splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    return meta
dirs = sorted(p for p in Path("skills").iterdir() if p.is_dir())
rows = []
print("#  技能                     類型    建議放置               對應範例")
for i, d in enumerate(dirs, 1):
    meta = front((d / "SKILL.md").read_text(encoding="utf-8"))
    name = meta.get("name", "?")
    kind = "任務型" if name in TASK else "常駐型"
    place = "自動觸發" if name in TASK else "明確呼叫／貼進 CLAUDE.md"
    rel = RELATED.get(name, "—")
    ok = "" if rel == "—" else (" ✅" if Path(rel).exists() else " ❌")
    desc = meta.get("description", "")[:90]
    print(f"{i:<2} {name:<24} {kind:<6} {place:<20} {rel}{ok}")
    rows.append(f"| {i} | {name} | {kind} | {place} | {rel} | {desc}… |")
readme = Path("skills/README.md").read_text(encoding="utf-8")
n_readme = int(re.search(r"(\d+) Agent Skills", readme).group(1))
n_table = len(re.findall(r"^\| \d+ \|", readme, re.MULTILINE))
n_plugin = int(json.loads(Path(".claude-plugin/plugin.json").read_text(encoding="utf-8"))["description"].split()[0])
mk = json.loads(Path(".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
n_market = int(mk["plugins"][0]["description"].split()[0])
print()
print(f"數量核對：資料夾 {len(dirs)}｜README 開頭 {n_readme}｜README 表格 {n_table} 列｜plugin.json {n_plugin}｜marketplace.json {n_market}")
same = len({len(dirs), n_readme, n_table, n_plugin, n_market}) == 1
print("結論：" + ("全部一致 ✅" if same else "有出入 ⚠️"))
out = work / "skill-map.md"
out.write_text("# 第 6 章技能地圖\n\n| # | 技能 | 類型 | 建議放置 | 對應範例 | description 前 90 字 |\n|---|---|---|---|---|---|\n" + "\n".join(rows) + "\n", encoding="utf-8")
print("已寫入 " + str(out))'
   show "$P"; py_run "$P" ;;
3) banner "技能也要被檢查：掃描 skills/ 與 .claude-plugin/"
   tip "技能就是提示詞，所以也能用 fable_scanner 靜態掃描，不呼叫模型。看作者的 11 個技能有沒有踩到他自己寫的規則；結束碼 1 表示至少有一個 error。"
   P='python -m fable_scanner scan skills > ../ch06/interactive/scan-skills.txt
echo "skills/ 掃描結束碼：$?（1 表示有 error）"
grep -v "^ *https" ../ch06/interactive/scan-skills.txt
echo
echo "──── 外掛設定檔 .claude-plugin/ ────"
python -m fable_scanner scan .claude-plugin | grep -v "^ *https"'
   show "$P"; sh_run "$P" ;;
4) banner "正規表達式不懂上下文：改寫副本消掉誤報"
   tip "refusal-aware-calling 第 18 行其實是在說「不要」這樣寫，但掃描器只比對字串，引述反例也照抓。複製一份到 ch06/interactive/ 改寫成不引用觸發詞的說法再掃，原檔一個字都不動。"
   P='echo "──── 原檔第 18 行 ────"
sed -n 18p skills/refusal-aware-calling/SKILL.md
echo
mkdir -p ../ch06/interactive/refusal-aware-calling
sed "s/.think step by step. or .explain your reasoning. framing/prompts that ask it to narrate its chain of thought/" skills/refusal-aware-calling/SKILL.md > ../ch06/interactive/refusal-aware-calling/SKILL.md
echo "──── 原檔與副本差異 ────"
diff --strip-trailing-cr skills/refusal-aware-calling/SKILL.md ../ch06/interactive/refusal-aware-calling/SKILL.md
echo
echo "──── 原檔掃描 ────"
python -m fable_scanner scan skills/refusal-aware-calling/SKILL.md | grep -v "^ *https"
echo
echo "──── 改寫後副本掃描 ────"
python -m fable_scanner scan ../ch06/interactive/refusal-aware-calling/SKILL.md | grep -v "^ *https"'
   show "$P"; sh_run "$P" ;;
5) banner "範圍圍欄的前置：先用工具輸出證明問題"
   tip "自己造一份 10 行 log（3 行故意壞掉），證明 sample_target.parse_log 不報錯、直接丟行。不呼叫模型；結果存成 probe.txt，下一步會附給模型當證據。"
   P='import sys
from pathlib import Path
sys.path.insert(0, "projects/04_refactor_legacy")
import sample_target as st
work = Path("../ch06/interactive").resolve()
work.mkdir(parents=True, exist_ok=True)
lines = [
    "2026-11-20T10:00:01 web01 severity=3 user=alice login ok",
    "2026-11-20T10:00:02 web01 severity=2 user=bob logout",
    "2026-11-20T10:00:03 web02 severity=10 user=carol brute force burst",
    "2026-11-20T10:00:04 web02 severity=4 user=dave sudo used",
    "2026-11-20T10:00:05 db01 severity=5 disk almost full",
    "2026-11-20T10:00:06 db01 severity=1 user=erin query slow",
    "2026-11-20T10:00:07 web03 severity=high user=frank port scan",
    "2026-11-20T10:00:08 web03 severity=2 user=gina password changed",
    "2026-11-20T10:00:09 web01 severity=3 user=hank file uploaded",
    "2026-11-20T10:00:10 db02 severity=6 user=ivy backup done",
]
log = work / "sample.log"
log.write_text("\n".join(lines) + "\n", encoding="utf-8")   # 每次覆寫，重跑結果一樣
events = st.parse_log(str(log))
report = [f"輸入 {len(lines)} 行，parse_log 回傳 {len(events)} 筆，少算 {len(lines) - len(events)} 筆，沒有任何錯誤訊息", "被默默丟掉的行："]
for no, line in enumerate(lines, 1):
    if st.parse_line(line) is None:
        report.append(f"  第 {no} 行：{line}")
report.append("原因：PATTERN 的 severity 只吃 1 位數字，且 user= 欄位必填；不符就 return None")
text = "\n".join(report)
print(text)
(work / "probe.txt").write_text(text + "\n", encoding="utf-8")
print()
print("已寫入 " + str(work / "probe.txt"))'
   show "$P"; py_run "$P" ;;
6) banner "同一個提問，掛技能 vs 不掛技能（呼叫模型 2 次）"
   tip "會呼叫模型 2 次（A、B 各 1 次，effort medium），約需 1～3 分鐘。使用者只是「問問題」，交付物應是診斷與建議。A 版 system 只有一句角色，B 版加上 scope-fence 與 evidence-bound-progress 兩份技能本文，比較有沒有越界、結論有沒有指向 probe.txt。模型輸出每次會變，照實看。"
   P='import claude_cli_client
from pathlib import Path
work = Path("../ch06/interactive").resolve()
probe = work / "probe.txt"
if not probe.exists():
    print("找不到 " + str(probe) + "，先跑第 5 步")
    raise SystemExit(0)
for old in work.glob("answer-*.md"):
    old.unlink()                          # 清掉上次的回答，免得呼叫失敗時拿舊檔充數
def body(name):
    return Path("skills/" + name + "/SKILL.md").read_text(encoding="utf-8").split("---", 2)[2].strip()
question = ("我們的 SIEM 解析器 parse_log 好像有時候少算幾行，怎麼回事？\n\n"
            "<sample_target.py>\n" + Path("projects/04_refactor_legacy/sample_target.py").read_text(encoding="utf-8") + "</sample_target.py>\n\n"
            "<probe.txt>\n" + probe.read_text(encoding="utf-8") + "</probe.txt>")
systems = {
    "A": "你是資深工程師。請用繁體中文回答。",
    "B": "你是資深工程師。請用繁體中文回答。\n\n" + body("scope-fence") + "\n\n" + body("evidence-bound-progress"),
}
client = claude_cli_client.Anthropic()
answers = {}
for tag, system in systems.items():
    print("呼叫模型：" + tag + " 版（system " + str(len(system)) + " 字）…", flush=True)
    try:
        msg = client.messages.create(model="claude-fable-5", system=system,
                                     output_config={"effort": "medium"},
                                     messages=[{"role": "user", "content": question}])
    except claude_cli_client.APIError as exc:
        print("  ❌ 呼叫失敗：" + str(exc))
        continue
    text = msg.content[0].text if msg.content else "（stop_reason=" + str(msg.stop_reason) + "，沒有內容）"
    answers[tag] = text
    (work / ("answer-" + tag + ".md")).write_text(text, encoding="utf-8")
fence = chr(96) * 3
side = ["README", "備份", "backup", "工單", "ticket", "test_", "單元測試"]
evidence = ["probe", "第 3 行", "第 5 行", "第 7 行", "severity=10", "severity=high"]
def cell(tag, fn):
    return str(fn(answers[tag])) if tag in answers else "—"
def row(label, fn):
    print(f"{label:<26} " + "  ".join(f"{cell(t, fn):>6}" for t in "AB"))
print()
print("指標                         A 版    B 版")
row("回答字數", len)
row("程式碼區塊數", lambda s: s.count(fence) // 2)
row("含改好的 def parse_line", lambda s: "是" if "def parse_line" in s else "否")
row("額外產出關鍵字次數", lambda s: sum(s.count(k) for k in side))
row("指向證據次數", lambda s: sum(s.count(k) for k in evidence))
for t in answers:
    print()
    print("──── " + t + " 版前 12 行（全文在 answer-" + t + ".md）────")
    print("\n".join(answers[t].splitlines()[:12]))
print()
print("本步呼叫次數：" + str(claude_cli_client.calls_made()))'
   show "$P"; py_run "$P" ;;
7) banner "Mythos 的邊界在外部閘門：基準＋3 份壞工作包"
   tip "Fable 的分類器不是 Mythos 的安全邊界，要在跑之前用 scope_gate.py 檢查授權、範圍、私有證據、獨立驗證、修補負責人。不呼叫模型：先跑兩份範例與自帶測試當基準，再複製出 3 份壞工作包到 ch06/interactive/gate/，看哪些被擋、哪些只是警告。"
   P='import copy, io, json, contextlib
from pathlib import Path
import mythos_scope.scope_gate as sg
import mythos_scope.test_scope_gate as tg
gate = Path("../ch06/interactive/gate").resolve()
gate.mkdir(parents=True, exist_ok=True)
def run(path):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = sg.main(str(path))
    print("──── " + Path(path).name + "（結束碼 " + str(code) + "，" + ("擋下" if code else "放行") + "）")
    print(buf.getvalue().rstrip())
print("== 基準：書附兩份範例 ==")
run("mythos_scope/sample_mythos_scope.json")
run("mythos_scope/sample_fable_scope.json")
for name in ("test_valid_mythos_scope_packet_is_clean", "test_mythos_requires_authorization_and_private_artifacts", "test_fable_packet_warns_without_refusal_path"):
    getattr(tg, name)()
    print("ok  " + name)
mythos = json.loads(Path("mythos_scope/sample_mythos_scope.json").read_text(encoding="utf-8"))
fable = json.loads(Path("mythos_scope/sample_fable_scope.json").read_text(encoding="utf-8"))
bad_forbidden = copy.deepcopy(mythos)
bad_forbidden["allowed_actions"] += ["public_poc", "exfiltration"]
bad_missing = copy.deepcopy(mythos)
for field in ("authorization_id", "glasswing_scope_id", "evidence_store", "human_patch_owner"):
    bad_missing.pop(field)
fable_no_tel = copy.deepcopy(fable)
fable_no_tel.pop("refusal_logging")
fable_no_tel.pop("fallbacks")
print()
print("== 3 份壞工作包 ==")
for fname, packet in (("bad-forbidden.json", bad_forbidden), ("bad-missing.json", bad_missing), ("fable-no-telemetry.json", fable_no_tel)):
    p = gate / fname
    p.write_text(json.dumps(packet, ensure_ascii=False, indent=2), encoding="utf-8")   # 每次覆寫，可重跑
    run(p)'
   show "$P"; py_run "$P" ;;
8) banner "總結：規則寫成技能才會留下"
   tip "把本章重點收成 6 句話，每句都連回前面 7 步看到的證據。"
   P='cat <<EOF
  第 6 章總結
    寫在對話裡的叮嚀會淡掉；寫成 SKILL.md 技能才會留下，還能當 Claude Code 外掛安裝
    11 個技能裡只有 effort-router、verifier-subagent、lesson-memory 會自動觸發，其餘常駐型要明確呼叫或貼進系統提示詞／CLAUDE.md
    範圍圍欄：提問的交付物是診斷與建議，不是動手修，也不附沒人要的備份、README、工單（第 6 步 A/B）
    證據綁定進度：每句結論都要指得到工具輸出，例如 probe.txt 的第 3／5／7 行（第 5 步）
    技能本身也能被掃描器檢查；正規表達式不懂上下文，引述反例也會被抓，要分辨真違規與誤報（第 3、4 步）
    Mythos 的邊界在外部閘門：授權、範圍、私有證據、獨立驗證、修補負責人缺一不可；Fable 缺拒答紀錄與備援只會 warn（第 7 步）
EOF
echo
echo "本章產出："
ls ../ch06/interactive'
   show "$P"; sh_run "$P" ;;
*) echo "用法：bash ch06.sh <步驟 1-8>"; exit 1 ;;
esac
