// Throwaway: measure Metal ray tracing API throughput (software RT on M1) against a ~200k triangle scene.
import Metal
import Foundation

let src = """
#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

struct Params { uint width; uint height; uint raysPerPixel; uint anyHit; float maxDist; float3 origin; };

kernel void trace(constant Params& p [[buffer(0)]],
                  primitive_acceleration_structure accel [[buffer(1)]],
                  device atomic_uint* hits [[buffer(2)]],
                  uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= p.width || gid.y >= p.height) return;
    intersector<triangle_data> isect;
    isect.set_triangle_cull_mode(triangle_cull_mode::none);
    isect.accept_any_intersection(p.anyHit != 0);
    isect.assume_geometry_type(geometry_type::triangle);
    uint seed = gid.x * 1973u + gid.y * 9277u + 26699u;
    uint local = 0;
    for (uint r = 0; r < p.raysPerPixel; r++) {
        seed = seed * 1664525u + 1013904223u; float a = (seed >> 8) * (1.0f/16777216.0f) * 6.2831853f;
        seed = seed * 1664525u + 1013904223u; float z = (seed >> 8) * (1.0f/16777216.0f) * 2.0f - 1.0f;
        float s = sqrt(max(0.0f, 1.0f - z*z));
        ray rr;
        rr.origin = p.origin + float3(float(gid.x)/p.width*200.0f - 100.0f, 0.0f, float(gid.y)/p.height*200.0f - 100.0f);
        rr.direction = normalize(float3(s*cos(a), z, s*sin(a)));
        rr.min_distance = 0.001f; rr.max_distance = p.maxDist;
        intersection_result<triangle_data> res = isect.intersect(rr, accel);
        if (res.type != intersection_type::none) local++;
    }
    atomic_fetch_add_explicit(hits, local, memory_order_relaxed);
}
"""

let device = MTLCreateSystemDefaultDevice()!
print("device:", device.name, "raytracing:", device.supportsRaytracing)
let lib = try device.makeLibrary(source: src, options: nil)
let fn = lib.makeFunction(name: "trace")!
let pso = try device.makeComputePipelineState(function: fn)
let queue = device.makeCommandQueue()!

// scene: heightfield grid 320x320 quads (~205k tris) plus 2000 random boxes (24k tris)
var verts: [SIMD3<Float>] = []
var idx: [UInt32] = []
let n = 320
for j in 0...n { for i in 0...n {
    let x = Float(i)/Float(n)*400 - 200, z = Float(j)/Float(n)*400 - 200
    let y = sin(x*0.05)*cos(z*0.05)*8
    verts.append(SIMD3(x, y, z)) } }
for j in 0..<n { for i in 0..<n {
    let a = UInt32(j*(n+1)+i), b = a+1, c = a+UInt32(n+1), d = c+1
    idx += [a,b,c, b,d,c] } }
var rng = SystemRandomNumberGenerator()
for _ in 0..<2000 {
    let cx = Float.random(in: -190...190, using: &rng), cz = Float.random(in: -190...190, using: &rng)
    let cy = Float.random(in: 5...60, using: &rng), h = Float.random(in: 2...10, using: &rng)
    let base = UInt32(verts.count)
    for dz in [-h, h] { for dy in [-h, h] { for dx in [-h, h] { verts.append(SIMD3(cx+dx, cy+dy, cz+dz)) } } }
    let faces: [[UInt32]] = [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]
    for f in faces { idx += [base+f[0],base+f[1],base+f[2], base+f[0],base+f[2],base+f[3]] }
}
print("triangles:", idx.count/3)
let vbuf = device.makeBuffer(bytes: verts, length: verts.count*MemoryLayout<SIMD3<Float>>.stride)!
let ibuf = device.makeBuffer(bytes: idx, length: idx.count*4)!
let geom = MTLAccelerationStructureTriangleGeometryDescriptor()
geom.vertexBuffer = vbuf; geom.vertexStride = MemoryLayout<SIMD3<Float>>.stride
geom.indexBuffer = ibuf; geom.indexType = .uint32; geom.triangleCount = idx.count/3
let desc = MTLPrimitiveAccelerationStructureDescriptor(); desc.geometryDescriptors = [geom]
let sizes = device.accelerationStructureSizes(descriptor: desc)
let accel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize)!
let t0 = Date()
var cb = queue.makeCommandBuffer()!
let enc = cb.makeAccelerationStructureCommandEncoder()!
enc.build(accelerationStructure: accel, descriptor: desc, scratchBuffer: scratch, scratchBufferOffset: 0)
enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
print(String(format: "BVH build: %.1f ms", Date().timeIntervalSince(t0)*1000))

struct Params { var width: UInt32; var height: UInt32; var rpp: UInt32; var anyHit: UInt32; var maxDist: Float; var pad: SIMD3<Float> = .zero; var origin: SIMD3<Float> }
for (w, h, rpp, any, maxd) in [(1280, 720, 1, 0, Float(1000)), (1280, 720, 1, 1, 1000), (1280, 720, 2, 1, 100), (1280, 720, 4, 1, 100), (640, 360, 4, 1, 100), (2560, 1440, 1, 1, 1000)] {
    var params = Params(width: UInt32(w), height: UInt32(h), rpp: UInt32(rpp), anyHit: UInt32(any), maxDist: maxd, origin: SIMD3(0, 30, 0))
    let hits = device.makeBuffer(length: 4)!
    var best = Double.infinity
    for _ in 0..<5 {
        memset(hits.contents(), 0, 4)
        cb = queue.makeCommandBuffer()!
        let ce = cb.makeComputeCommandEncoder()!
        ce.setComputePipelineState(pso)
        ce.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        ce.setAccelerationStructure(accel, bufferIndex: 1)
        ce.setBuffer(hits, offset: 0, index: 2)
        ce.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        ce.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        best = min(best, cb.gpuEndTime - cb.gpuStartTime)
    }
    let rays = Double(w*h*rpp)
    let hitCount = hits.contents().load(as: UInt32.self)
    print(String(format: "%dx%d x%d rays anyhit=%d maxdist=%.0f: %.2f ms  (%.0f Mrays/s, hit %.0f%%)", w, h, rpp, any, maxd, best*1000, rays/best/1e6, Double(hitCount)/rays*100))
}
