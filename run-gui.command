#!/bin/zsh

set -eu

project_dir="${0:A:h}"
port=8765

cd "$project_dir"
python3 -m http.server "$port" --bind 127.0.0.1 --directory WebUI >/tmp/jev-bassist-gui.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM
sleep 0.5
if open -Ra "Google Chrome"; then
  open -a "Google Chrome" "http://127.0.0.1:$port"
else
  open "http://127.0.0.1:$port"
fi
echo "Jev Bassist GUI: http://127.0.0.1:$port"
echo "Press Control-C to stop the GUI server."
wait "$server_pid"
