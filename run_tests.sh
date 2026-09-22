#!/usr/bin/env bash
# Headless verification for the VN Dialogue Demo project.
# Usage: ./run_tests.sh [path-to-godot-binary]
set -uo pipefail

GODOT="${1:-${GODOT:-/home/user/.local/godot/Godot_v4.7.2-stable_linux.x86_64}}"
cd "$(dirname "$0")"

if [ ! -x "$GODOT" ]; then
  echo "Godot binary not found at $GODOT" >&2
  echo "Download: https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip" >&2
  exit 2
fi

echo "== Godot version =="
"$GODOT" --version

echo
echo "== Importing project (editor headless) =="
"$GODOT" --headless --import 2>&1 | grep -vE "^\s*$" | tee /tmp/vn_import.log | tail -20

echo
echo "== Script checks =="
for s in scenes/vn_balloon.gd scenes/vn_scene.gd autoloads/game_state.gd tests/test_vn_ui.gd scenes/route_graph/route_graph_view.gd scenes/route_graph/route_graph_compiler.gd scenes/route_graph/route_graph_mesh_builder.gd scenes/route_graph/route_graph_atlas.gd; do
  if "$GODOT" --headless --check-only --script "res://$s" >/tmp/vn_check.log 2>&1; then
    echo "  [OK]   $s"
  else
    echo "  [ERR]  $s"; cat /tmp/vn_check.log; exit 1
  fi
done

echo
echo "== Running headless UI test-suite =="
"$GODOT" --headless res://tests/test_vn_ui.tscn 2>&1 | tee /tmp/vn_test.log
TEST_EXIT=${PIPESTATUS[0]}

echo
echo "== Running route-graph check =="
"$GODOT" --headless res://tests/test_route_graph.tscn 2>&1 | tee /tmp/vn_route.log
ROUTE_EXIT=${PIPESTATUS[0]}

echo
echo "== Scanning logs for runtime errors =="
grep -nE "SCRIPT ERROR|Parse Error|ERROR:" /tmp/vn_test.log /tmp/vn_route.log /tmp/vn_import.log | grep -v "errors_panel" || echo "  no script/parse errors found"

echo
echo "ui exit code: $TEST_EXIT"
echo "route-graph exit code: $ROUTE_EXIT"
if [ "$TEST_EXIT" -ne 0 ] || [ "$ROUTE_EXIT" -ne 0 ]; then
  exit 1
fi
exit 0
