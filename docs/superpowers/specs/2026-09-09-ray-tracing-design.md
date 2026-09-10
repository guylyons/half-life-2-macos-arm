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

## Implementation status (2026-09-10)

What was built differs from the phase-1 plan above in these ways:

- **Geometry.** Three classes, all in one Metal instance acceleration structure:
  world brushes and displacements (instance 0); all static props merged into
  one mesh (pulled through `IStudioRender::GetTriangles`, LOD 0, translucent
  and alpha-tested materials left out); dynamic objects per frame. Rigid
  dynamic meshes (physics props, doors, brush entities) carry a prebuilt BVH
  and are instanced with the entity transform; skinned models (NPCs, ragdolls)
  are skinned on the GPU from the client's bone matrices into a per-object
  world-space copy that is refitted every frame. `rt_dynamic 0/1/2`,
  `rt_static_props`, `rt_list_dynamic`, `rt_list_props`.
- **Sun shadows** darken only where a dynamic object blocks a point that the
  world brushes leave sunlit, so the lightmaps' own shadows are not doubled.
  The sun direction follows vrad's construction (`SetupLightNormalFromProps`,
  negated). Metal instance masks proved unreliable on the M1 software tracer,
  so hits are walked along the ray and classified by instance id. A per-object
  bounds pre-test limits shadow rays to the objects' footprints. On by default.
- **Pipeline.** Asynchronous with two frames of latency: the depth captured at
  frame N is traced at N+1 (after a GL fence, never a finish) and composited at
  N+2 by a GL shader that reconstructs each pixel from the current depth,
  projects it into the traced frame and takes a depth-weighted bilinear of the
  half-resolution samples. Three rotating slots of IOSurfaces. The GPU overlaps
  the GL frame with the tracer; the render thread no longer stalls.
  `rt_async 0` is the synchronous path.
- **Denoise.** Temporal accumulation (up to 32 samples) with reprojection and
  3x3 neighbourhood variance clipping, per-pixel R2 sample sequences, a
  depth- and normal-aware blur whose radius shrinks as the history converges.
- **Cost** (M1 Pro, 1512x982, half-resolution trace, plaza scene with 18 NPCs):
  ~5 ms GPU per traced frame, 176 fps; 62 fps with full-resolution tracing.
  A bounded GPU wait disables the layer on a hang or fault instead of freezing
  the game.
- **Not done:** reflections; alpha-tested geometry (fences, foliage) is absent
  from the BVH rather than texture-tested; the engine's projected NPC shadows
  still draw alongside the traced ones.
