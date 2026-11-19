"""第 6 章練習 2：A/B 對照（A：只有角色；B：角色＋scope-fence＋evidence-bound-progress），共 2 次 claude -p。"""
import re
import sys
from pathlib import Path

PRACTICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PRACTICE))
import claude_cli_client  # noqa: E402

claude_cli_client.install()

CH06 = PRACTICE / "ch06"
FABLE5 = PRACTICE / "fable5"
ROLE = "你是資深工程師"


def skill_body(name):
    """讀 SKILL.md 並去掉開頭的 --- frontmatter 區塊。"""
    text = (FABLE5 / "skills" / name / "SKILL.md").read_text(encoding="utf-8")
    return re.sub(r"\A---\n.*?\n---\n", "", text, count=1, flags=re.DOTALL).strip()


def build_user_message():
    target = (FABLE5 / "projects" / "04_refactor_legacy" / "sample_target.py").read_text(encoding="utf-8")
    probe = (CH06 / "probe.txt").read_text(encoding="utf-8")
    return ("我們的 SIEM 解析器 parse_log 好像有時候少算幾行，怎麼回事？\n\n"
            f"## sample_target.py\n\n```python\n{target}```\n\n## probe.txt\n\n```text\n{probe}```")


def ask(system):
    resp = claude_cli_client.Anthropic().messages.create(
        model="claude-fable-5", max_tokens=4000, system=system,
        messages=[{"role": "user", "content": build_user_message()}],
    )
    if resp.stop_reason == "refusal" or not resp.content or not resp.content[0].text.strip():
        raise RuntimeError(f"沒有拿到回答（stop_reason={resp.stop_reason}）")
    return resp.content[0].text


def main():
    variants = {
        "A": ROLE,
        "B": f"{ROLE}\n\n{skill_body('scope-fence')}\n\n{skill_body('evidence-bound-progress')}",
    }
    for key, system in variants.items():
        try:
            answer = ask(system)
        except (OSError, RuntimeError) as e:
            print(f"錯誤（{key} 版）：{e}", file=sys.stderr)
            sys.exit(1)
        out = CH06 / f"answer-{key}.md"
        out.write_text(f"# {key} 版回答（system {len(system)} 字元）\n\n---\n\n{answer}\n", encoding="utf-8")
        print(f"{key} 版：system {len(system)} 字元 → {out.name}（{len(answer)} 字元）")
    print(f"claude -p 呼叫次數：{claude_cli_client.calls_made()}")


if __name__ == "__main__":
    main()
