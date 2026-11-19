記憶處理器的大小上限只在 create 時檢查，str_replace 與 insert 可以把檔案撐過 32,000 bytes。

細節：第 3 章練習 1 先建一個 12 bytes 的小檔，再用 str_replace 換成 10,667 個中文字，處理器回「edited small.md」，檔案變成 32,003 bytes；insert 也一樣寫到 32,025 bytes。修正版把檢查放在共用的寫入函式後，兩個情境都被拒絕。

為什麼重要：上限是防止記憶無限膨脹的唯一閘門，只守一個入口等於沒守。

provenance：ch03/guard-results.txt 情境 5、6 的輸出；修正後的對照見 ch03/guard-results-fixed.txt。
