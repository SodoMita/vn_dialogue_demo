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

echo "== Asset rules (WebP only) =="
bash tests/check_assets.sh || exit 1

echo "== Godot version =="
"$GODOT" --version

echo
echo "== Importing project (editor headless) =="
"$GODOT" --headless --import 2>&1 | grep -vE "^\s*$" | tee /tmp/vn_import.log | tail -20

echo
echo "== Script checks =="
for s in scenes/vn_balloon.gd scenes/panic_screen.gd scenes/hold_indicator.gd scenes/vn_scene.gd autoloads/game_state.gd autoloads/audio_director.gd tests/test_vn_ui.gd scenes/route_graph/route_graph_view.gd scenes/route_graph/route_graph_compiler.gd scenes/route_graph/route_graph_mesh_builder.gd scenes/route_graph/route_graph_atlas.gd scenes/route_graph/route_graph_panel.gd scenes/route_graph/route_graph_travel.gd scenes/motion/stage_director.gd scenes/motion/sprite_3d_quad.gd scenes/stage/stage_tag_parser.gd scenes/stage/stage_actors.gd scenes/stage/actor_definition.gd tests/test_staging.gd; do
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
echo "== Running panic-return check =="
"$GODOT" --headless res://tests/test_panic_return.tscn 2>&1 | tee /tmp/vn_panic.log
PANIC_EXIT=${PIPESTATUS[0]}

echo
echo "== Running motion-director check =="
"$GODOT" --headless res://tests/motion_director_test.tscn 2>&1 | tee /tmp/vn_motion.log
MOTION_EXIT=${PIPESTATUS[0]}

echo
echo "== Running staging (short tags / restore) check =="
"$GODOT" --headless res://tests/test_staging.tscn 2>&1 | tee /tmp/vn_staging.log
STAGING_EXIT=${PIPESTATUS[0]}

echo
echo "== Scanning logs for runtime errors =="
grep -nE "SCRIPT ERROR|Parse Error|ERROR:" /tmp/vn_test.log /tmp/vn_route.log /tmp/vn_import.log /tmp/vn_panic.log /tmp/vn_motion.log /tmp/vn_staging.log | grep -v "errors_panel" || echo "  no script/parse errors found"

echo
echo "ui exit code: $TEST_EXIT"
echo "route-graph exit code: $ROUTE_EXIT"
echo "panic-return exit code: $PANIC_EXIT"
echo "motion exit code: $MOTION_EXIT"
echo "staging exit code: $STAGING_EXIT"
if [ "$TEST_EXIT" -ne 0 ] || [ "$ROUTE_EXIT" -ne 0 ] || [ "$PANIC_EXIT" -ne 0 ] || [ "$MOTION_EXIT" -ne 0 ] || [ "$STAGING_EXIT" -ne 0 ]; then
  exit 1
fi
exit 0
