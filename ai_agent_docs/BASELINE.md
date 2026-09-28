# PR1 baseline (branch remi-q7x, from main @ 3b382c5)

Godot 4.7.2 headless, `bash run_tests.sh`:

- UI suite: **391 passed, 8 failed** (pre-existing; headless audio/skip timing):
  - Rook's voiced line plays a voice clip on the Voice bus
  - Skip key toggles skip mode off
  - Skip button enables skip mode
  - skip mode ran to the next choices
  - Resume continues the current voice clip
  - dialogue resumes waiting after panic
  - backlog holds every line incl. seeked-past ones
  - history panel scrolls down to the focused row
- route-graph: 189 passed, 0 failed
- panic-return: exit 0

Any new failure beyond this list is a regression.
