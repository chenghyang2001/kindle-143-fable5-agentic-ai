canary 第一次執行只建立基準線的結果快照，不會做任何比較。

細節：`canary run` 讀到 baseline.json 裡還沒有 outcomes 時，會把這次的拒答、延遲、分數寫成基準並印出「first run -- snapshot captured as baseline outcomes」，之後的執行才會跟它比對。所以第一次看到沒有任何告警是正常的，不代表模型沒有漂移。

為什麼重要：如果把第一次的「沒告警」當成驗證通過，就會錯過基準本身就是壞的情況。

provenance：fable5/fable_scanner/canary.py 第 101～105 行（outcomes 為空時寫入基準並印出 first run 訊息）。
