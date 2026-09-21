# Route graph — design notes (future work)

A visual route/flow graph of the story is planned. **Status: deferred.** Godot's immediate
Canvas drawing is too slow for a graph of this size, so the plan is a custom single-pass
renderer — effectively a small graphics engine from scratch.

## Rendering architecture

- **One draw call.** A single surface/mesh rendered by one shader pass; no per-node
  CanvasItems.
- **CPU builds the buffers.** Vertices carry `position` + `uv`; the CPU generates the quad
  soup (node rects, port labels, arrows) whenever the graph changes and uploads it once.
- **Everything glyph-shaped is a texture.** Text, symbols and slot/line thumbnails are
  baked into a texture atlas; the fragment shader samples the atlas via the vertex uv.
- **Nodes are rects** whose left edge hosts named *input* ports and right edge named
  *output* ports; arrows connect output → input ports.
- **Conditions are written on the graph** (edge labels / node annotations), sourced from
  the `if`/`do` metadata compiled from the `.dialogue` files.

## Work breakdown (rough)

1. Atlas baker: rasterize labels/symbols/thumbnails into a WebP/RGBA atlas + uv table.
2. CPU mesh builder: node layout (layered DAG), port slots, arrow geometry (curves as
   triangle strips), condition-label quads.
3. Shader: single pass sampling the atlas; optional pan/zoom via uniform transform.
4. Data source: compile `dialogue/*.dialogue` to nodes/edges (cues, choices, conditions).
5. Integration: editor-style overlay panel + a player-facing "story map" if desired.

Estimated large; kept out of the v1.x line on purpose.
