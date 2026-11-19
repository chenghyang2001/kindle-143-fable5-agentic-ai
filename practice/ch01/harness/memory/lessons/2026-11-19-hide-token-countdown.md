不要在提示詞裡讓模型看到自己還剩多少 token；Fable 5 看到倒數會提早收尾。

細節：
- 舊版提示詞寫了「128000 個 token 可用，請好好規劃」這類句子，掃描器直接判 error。
- 改法：系統提示詞加「上下文平靜」小節，要求不提剩餘空間、不為篇幅刪工作。
- 為什麼重要：夜間迴圈要把測試修到全綠，提早收尾等於把半套修正交出去。

provenance：`cd fable5 && PYTHONUTF8=1 python -m fable_scanner scan fable_scanner/examples/bad_prompt.md` 輸出第 21 行 FS-01（error）；規則定義在 fable5/fable_scanner/rules.py 第 106～117 行。
