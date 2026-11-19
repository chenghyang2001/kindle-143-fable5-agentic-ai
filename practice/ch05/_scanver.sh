#!/bin/bash
# 用法：bash ../ch05/_scanver.sh <版本號>（在 fable5/ 下執行）
F=../ch05/fixed_prompt.md
cp "$F" "../ch05/fixed_prompt.v$1.md"
PYTHONUTF8=1 python -m fable_scanner scan "../ch05/fixed_prompt.v$1.md" > "../ch05/scan-v$1.txt" 2>&1
echo "rc=$?" >> "../ch05/scan-v$1.txt"
cat "../ch05/scan-v$1.txt"
