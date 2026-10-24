#!/bin/zsh
set -e
cd -- "${0:A:h}"
for ncm_python in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if [[ -x "$ncm_python" ]]; then
    exec "$ncm_python" web/start.py
  fi
done
print '未找到 Python 3。'
read -k 1
