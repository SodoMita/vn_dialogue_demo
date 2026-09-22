# Route graph

Optional story map, opened from the **Map** button. It is not required for the rest of
the VN. **Status: implemented** in `scenes/route_graph/`.

Godot's immediate Canvas drawing is too slow for a graph of this size, so the map is a
small graphics engine: one mesh, one shader pass, one texture atlas.

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

## What shipped

1. Atlas baker (`route_graph_atlas.gd`): white texel, port icons, and labels blitted from
   the font glyph cache into one RGBA atlas. Settings → Glyph scale (1×–4×, default 2×) is the
   texel density of those symbols, not the atlas capacity. The side starts at 1024 and doubles
   until the sharper glyphs fit (cap 4096). Quads stay the same graph size; the UVs cover more
   texels, so zoom stays sharp. Map filter swaps only the sampler hint (nearest, linear, or
   mipmapped) — still one `texture()` fetch and no branches. Node titles, port tags, condition
   badges and the subtitle are translated when the atlas is baked, not at compile time, so a
   language switch rebakes the same graph. Dialogue text uses the `dialogue` catalog; cue names,
   END and format strings use the UI catalog.
2. CPU mesh builder (`route_graph_mesh_builder.gd`): layered layout, port slots, straight
   edges, condition badges on the ports. No grid and no editing.
3. Shader (`route_graph.gdshader`): one pass, pan/zoom in the vertex stage, exactly one
   `texture()` fetch, no loops or branches.
4. Compiler (`route_graph_compiler.gd`): every `res://dialogue/*.dialogue` file, in path
   order. Cues, choice groups, and one shared END. The graph may contain cycles; a
   back-edge is drawn but does not move the anchors. The first cue of the first file is
   always the leftmost node, and END is always the rightmost. Linear lines and mutations
   collapse. A port click jumps to the other side of that line. An edge click — including
   the arrow — jumps to the further of that edge's two nodes, not the source and not a
   node past the edge. A header click travels to that place in the game.
5. Player overlay: the Map button on the system row. Drag pans; pinch or the wheel zooms around the fingers or cursor. The current scene is marked on the
   graph and named in the bar. **Visited only** is on by default and hides routes the
   player has not reached. Turning it off asks for approval before showing spoilers.

The route-graph scripts are preloaded. They intentionally have no `class_name` and no
typed `_init` arguments — a missing UID class-cache entry otherwise fails to parse
`RouteGraphMeshBuilder._init` and the panel then treats the view as a bare Control.
