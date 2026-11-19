"""第 18 章練習 1：10 項硬閘門的上線判定（不呼叫模型）。

規則：每一項的 value 必須是 true（JSON 布林）「而且」evidence 指向的檔案真的存在且非空，否則視為 false。
兩個 Mythos 閘門只有在 model 是 claude-fable-5 時才可以是 "not_applicable"。
任何一項不是 PASS／N/A → NO-GO（exit 1）；全部通過 → GO（exit 0）。

用法：PYTHONUTF8=1 python ch18/go_no_go.py [deployment.json]
"""
import json
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
GATES = [
    "model_variant_documented", "retention_resolved", "fable_refusal_path_wired", "fallback_gap_handled",
    "mythos_scope_packet_required", "mythos_artifact_controls_on", "memory_gate_on", "mcp_least_privilege",
    "injection_boundary_set", "verifier_running",
]
MYTHOS_ONLY = {"mythos_scope_packet_required", "mythos_artifact_controls_on"}
FABLE = "claude-fable-5"


def evidence_ok(ev, root=PRACTICE):
    """證據要是 practice/ 底下真的存在、非空的檔案；"none"、空字串、跳出 practice/ 的路徑都不算。"""
    if not isinstance(ev, str) or ev.strip().lower() in ("", "none"):
        return False, "沒有證據"
    path = (root / ev).resolve()
    if root.resolve() not in path.parents:
        return False, f"證據路徑跳出 practice/：{ev}"
    if not path.is_file():
        return False, f"證據檔不存在：{ev}"
    if path.stat().st_size == 0:
        return False, f"證據檔是空的：{ev}"
    return True, ev


def judge(gate, entry, model, root=PRACTICE):
    """回傳 (結果, 理由)，結果是 PASS／N/A／FAIL。"""
    if not isinstance(entry, dict):
        return "FAIL", "缺少這一項"
    value = entry.get("value")
    if value == "not_applicable":
        if gate in MYTHOS_ONLY and model == FABLE:
            return "N/A", f"model 是 {FABLE}，不適用 Mythos 閘門"
        return "FAIL", "這一項不可以標 not_applicable"
    if value is not True:  # 只接受 JSON 布林 true，"true"、1 都不算
        return "FAIL", f"value={value!r}"
    ok, why = evidence_ok(entry.get("evidence"), root)
    return ("PASS", why) if ok else ("FAIL", f"value=true 但{why}")


def main(argv):
    path = Path(argv[0]) if argv else Path(__file__).with_name("deployment.json")
    try:
        dep = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"錯誤：讀不到或解析不了 {path}：{e}", file=sys.stderr)
        return 1  # 讀不到清單本身就是 NO-GO
    model, gates = dep.get("model"), dep.get("gates") or {}
    print(f"部署：{dep.get('deployment')}\nmodel：{model}\n")
    print(f"{'#':<3} {'閘門':<30} {'結果':<5} 理由")
    results = []
    for i, gate in enumerate(GATES, 1):
        res, why = judge(gate, gates.get(gate), model)
        results.append(res)
        print(f"{i:<3} {gate:<30} {res:<5} {why}")
    unknown = sorted(set(gates) - set(GATES))
    if unknown:
        print(f"\n注意：清單裡有未定義的閘門 {unknown}（不影響判定）")
    passed = sum(r == "PASS" for r in results)
    na = sum(r == "N/A" for r in results)
    go = all(r in ("PASS", "N/A") for r in results)
    print(f"\nPASS {passed}、N/A {na}、FAIL {len(results) - passed - na}")
    print("最終判定：" + ("GO" if go else "NO-GO"))
    return 0 if go else 1


def _selftest():
    assert judge("memory_gate_on", {"value": True, "evidence": "ch03/scan-output.txt"}, FABLE)[0] == "PASS"
    assert judge("memory_gate_on", {"value": True, "evidence": "none"}, FABLE)[0] == "FAIL"
    assert judge("memory_gate_on", {"value": True, "evidence": "ch99/not-there.txt"}, FABLE)[0] == "FAIL"
    assert judge("memory_gate_on", {"value": "true", "evidence": "ch03/scan-output.txt"}, FABLE)[0] == "FAIL"
    assert judge("memory_gate_on", {"value": True, "evidence": "../CLAUDE.md"}, FABLE)[0] == "FAIL"
    assert judge("mythos_scope_packet_required", {"value": "not_applicable"}, FABLE)[0] == "N/A"
    assert judge("mythos_scope_packet_required", {"value": "not_applicable"}, "claude-mythos-5")[0] == "FAIL"
    assert judge("verifier_running", {"value": "not_applicable"}, FABLE)[0] == "FAIL"
    assert judge("retention_resolved", None, FABLE)[0] == "FAIL"


if __name__ == "__main__":
    _selftest()
    sys.exit(main(sys.argv[1:]))
