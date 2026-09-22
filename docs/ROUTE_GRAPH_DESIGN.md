# Route graph — single-pass choice graph renderer

A visual route/flow graph of the story. Godot's immediate Canvas drawing is too slow for a
graph of this size, so this is a custom single-pass renderer — a small graphics engine.

**Status: implemented** in `route_graph/`. Open it in play with the system-row **Map**
button (story map overlay). Drag to pan, wheel to zoom, click a visited node to jump.

## Rendering architecture

- **One draw call.** A single `ArrayMesh` surface rendered by one canvas_item shader pass;
  no per-node CanvasItems.
- **CPU builds the buffers.** Vertices carry `position` + `uv`; the CPU generates the quad
  soup (node rects, port labels, arrows) whenever the graph changes and uploads it once.
- **Everything glyph-shaped is a texture.** Text, symbols and slot/line thumbnails are
  baked into a RGBA atlas; the fragment shader samples the atlas via the vertex uv.
- **Nodes are rects** whose left edge hosts named *input* ports and right edge named
  *output* ports; arrows connect output → input ports (cubic ribbons + arrow heads).
- **Conditions are written on the graph** (edge labels / node annotations), sourced from
  the `if`/`do` metadata compiled from the `.dialogue` files.
- **Pan/zoom** is a shader uniform transform (`u_pan`, `u_zoom`, `u_origin`) so the mesh
  is not rebuilt while navigating.

## Modules

1. `route_graph_atlas.gd` — rasterize labels/symbols/thumbnails into an RGBA atlas + uv table.
2. `route_graph_mesh.gd` — CPU mesh builder: node layout is applied first, then port slots,
   bezier arrow ribbons, condition-label quads.
3. `route_graph.gdshader` — single pass sampling the atlas; pan/zoom via uniform transform.
4. `route_graph_compiler.gd` — compile `dialogue/*.dialogue` (via `DialogueResource.lines`)
   to nodes/edges (cues, choices, conditions, mutations, gotos).
5. `route_graph_layout.gd` — layered DAG (longest-path layers + barycenter ordering).
6. `route_graph_view.gd` — overlay Control that issues one `draw_mesh` and handles input.
7. Integration: authored `RouteGraphPanel` on the balloon + player-facing **Map** button.
