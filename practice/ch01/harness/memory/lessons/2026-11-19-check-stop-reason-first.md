讀回應內容之前先看 stop_reason；refusal 是迴圈事件，不是例外。

細節：
- 被拒答時 HTTP 仍是 200、content 可能是空的，直接讀 content[0].text 會拿到空字串或 IndexError。
- 正確做法：先判斷 stop_reason == "refusal"，記錄後走備援或跳過這一輪，再讀內容。
- 練習 1 的 try_prompt.py 照這個順序寫：先擋 refusal、再擋空回應，才寫檔。
- 為什麼重要：夜間迴圈沒人看著，把空回應當成「修好了」會讓驗證被假結果污染。

provenance：fable5/agentic_soc/triage_loop.py 第 37 行 `if msg.stop_reason == "refusal":`；fable5/README.md 最後一節第 4 點；ch01/try_prompt.py 的 ask()。
