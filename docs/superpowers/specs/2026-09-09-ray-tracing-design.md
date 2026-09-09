# Ray-traced lighting layer for Half-Life 2 on Apple Silicon: design

Date: 2026-09-09. Follows the port spec (`2026-09-09-hl2-arm64-port-design.md`).

## Goal

Add ray-traced ambient occlusion, sun shadows and (later) reflections to the
arm64 build, computed in Metal against the level geometry and composited onto
the Source renderer's frame. Toggle with `rt_enable`.

## Spike results (this M1 Pro, macOS 26)

- Metal ray tracing API works in software: ~180 M rays/s against 229k triangles.
  Any-hit rays are not cheaper. 1 ray/pixel at 1280x720 costs ~6 ms.
- OpenGL <-> Metal sharing through IOSurface-backed textures works and a full
  2560x1440 round trip (GL flush, Metal compute, GL blit, finish) costs ~2 ms.

Design point: trace at half resolution, 1 ray per pixel per effect per frame,
temporal accumulation over ~8 frames plus a small spatial filter.

## Architecture

```
client (game/client)                     render thread (shaderapi/togl)         Metal
--------------------                     ------------------------------         -----
LevelInitPostEntity: parse .bsp  ---->   IRayTracer::SetWorldGeometry  ------>  BVH build
CViewRender::RenderView end:
  material vars: matrices, sun,          RayTraceComposite shader DrawPass:
  settings on "rt/composite"             togl exports backbuffer FBO/depth
  DrawScreenSpaceQuad(material)  ---->   IRayTracer::ApplyAndComposite  ---->  trace + denoise
                                         GL: resolve depth -> IOSurface,        (reads depth
                                             composite result onto backbuffer    IOSurface,
                                                                                  writes result)
```

- `rtmetal/` (new module, ObjC++, `librtmetal.dylib`): Metal device, BVH,
  compute kernels (primary reconstruction from depth, AO rays, shadow rays,
  temporal accumulation, blur), IOSurface textures. Exposes `IRayTracer` via
  `CreateInterface`.
- `togl`: exports `GLMRT_GetBackbufferInfo()` (FBO ids, color/depth attachment
  names, size, MSAA) and `GLMRT_ResolveDepth()` (blit MSAA depth to a
  single-sample depth texture, then a GLSL pass packing 24-bit depth into an
  RGBA8 IOSurface-backed texture) and `GLMRT_Composite()` (GLSL fullscreen quad
  that multiplies the RT result onto the backbuffer). togl compiles its own GLSL
  directly, so no Direct3D bytecode is involved.
- `materialsystem/stdshaders`: new shader `RayTraceComposite` whose draw pass
  (on the render thread, GL context current) reads the material's vars and
  calls `IRayTracer::ApplyAndComposite`. The client draws a fullscreen quad with
  material `rt/composite` after screen-space effects and before the HUD. Matrix
  and sun parameters travel as material vars so they stay in sync with the
  queued render thread.
- `game/client`: BSP parsing (vertices, edges, surfedges, faces, texinfo flags
  to skip sky/nodraw/trigger, displacements), `light_environment` from the map
  entity string, `rt_*` convars, the composite draw.

## Effects

1. AO: N hemisphere rays (cosine weighted, max distance `rt_ao_radius` world
   units) from the reconstructed world position; visibility accumulated
   temporally; composite darkens by `rt_ao_strength`.
2. Sun shadows: one ray toward the sun direction (jittered within
   `rt_sun_angle` degrees); pixels facing the sun that are occluded are
   darkened by `rt_shadow_strength`. Lightmaps already contain static shadows,
   so this mostly adds contact shadows for props and characters.
3. Reflections (follow-on): needs a material mask; not in this spec's scope.

Geometry in the BVH: world brushes and displacements (static). Static props
and dynamic entities are follow-ons; they receive but do not cast in phase 1.

## Data flow per frame

1. Client computes `worldToView`, `viewToProjection` via
   `render->GetMatricesForView` and sets them plus camera origin, sun
   direction, near/far and the `rt_*` settings on the composite material.
2. Client draws the composite quad. The shader draw pass runs on the render
   thread and calls `ApplyAndComposite(params)`.
3. togl resolves depth into the shared IOSurface (GL flush).
4. Metal: reconstruct position/normal from depth, trace, accumulate, filter,
   write result (R = AO, G = sun visibility) to the shared result IOSurface.
   Command buffer waited synchronously (2 ms budget measured).
5. togl composites the result onto the current backbuffer FBO with a GLSL
   quad and multiplicative blending.

## Error handling

- No Metal device or ray tracing unsupported: `rt_enable` forces 0 with a
  console message; the composite draws nothing.
- Missing geometry (map failed to parse): effects disabled for that map.
- Any GL error in the resolve/composite path disables RT for the session
  with a message, never crashes.

## Testing

- Unit-ish: BSP parser on `d1_trainstation_01.bsp` yields a plausible triangle
  count and bounds; BVH build time under 2 s.
- Visual: `rt_debug 1` shows the raw AO buffer, `rt_debug 2` the shadow
  buffer, `rt_debug 3` the reconstructed normals.
- Performance: `cl_showfps 2` at 2560x1440 with RT on stays above 60 fps.
- Alignment: a moving camera shows no swimming between geometry and AO.
