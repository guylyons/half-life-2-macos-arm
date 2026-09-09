// Throwaway: measure GL -> Metal -> GL round trip through IOSurface-backed textures at 2560x1440.
import Foundation
import OpenGL
import OpenGL.GL3
import Metal
import IOSurface
import QuartzCore

let W = 2560, H = 1440
func makeSurface() -> IOSurface {
    return IOSurface(properties: [.width: W, .height: H, .bytesPerElement: 4, .pixelFormat: 0x42475241 /* 'BGRA' */])!
}
// --- GL context (offscreen)
var pf: CGLPixelFormatObj? = nil; var npix: GLint = 0
let attrs: [CGLPixelFormatAttribute] = [kCGLPFAAccelerated, kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(rawValue: UInt32(kCGLOGLPVersion_GL4_Core.rawValue)), CGLPixelFormatAttribute(rawValue: 0)]
CGLChoosePixelFormat(attrs, &pf, &npix)
var ctx: CGLContextObj? = nil
CGLCreateContext(pf!, nil, &ctx)
CGLSetCurrentContext(ctx)
print("GL:", String(cString: glGetString(GLenum(GL_VERSION))))

func glSurfaceTexture(_ s: IOSurface) -> GLuint {
    var tex: GLuint = 0
    glGenTextures(1, &tex)
    glBindTexture(GLenum(GL_TEXTURE_RECTANGLE), tex)
    let err = CGLTexImageIOSurface2D(ctx!, GLenum(GL_TEXTURE_RECTANGLE), GLenum(GL_RGBA8), GLsizei(W), GLsizei(H), GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), unsafeBitCast(s, to: IOSurfaceRef.self), 0)
    if err != kCGLNoError { print("CGLTexImageIOSurface2D error", err.rawValue) }
    return tex
}
let sceneSurf = makeSurface(), rtSurf = makeSurface()
let sceneTex = glSurfaceTexture(sceneSurf), rtTex = glSurfaceTexture(rtSurf)
var fbo: GLuint = 0
glGenFramebuffers(1, &fbo)
glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_RECTANGLE), sceneTex, 0)
print("fbo status:", glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE) ? "complete" : "INCOMPLETE")
// composite FBO targeting a plain texture, sampling rtTex (simulates the engine drawing the RT result)
var outTex: GLuint = 0
glGenTextures(1, &outTex); glBindTexture(GLenum(GL_TEXTURE_2D), outTex)
glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(W), GLsizei(H), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), nil)
var fbo2: GLuint = 0
glGenFramebuffers(1, &fbo2); glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo2)
glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), outTex, 0)
// blit via read/draw framebuffers (cheap stand-in for a fullscreen composite quad)
var fboRead: GLuint = 0
glGenFramebuffers(1, &fboRead); glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), fboRead)
glFramebufferTexture2D(GLenum(GL_READ_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_RECTANGLE), rtTex, 0)

// --- Metal
let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void proc(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
  float4 c = src.read(gid);
  dst.write(float4(1.0 - c.rgb, 1.0), gid);
}
"""
let pso = try device.makeComputePipelineState(function: try device.makeLibrary(source: src, options: nil).makeFunction(name: "proc")!)
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
td.usage = [.shaderRead, .shaderWrite]
let mScene = device.makeTexture(descriptor: td, iosurface: unsafeBitCast(sceneSurf, to: IOSurfaceRef.self), plane: 0)!
let mRT = device.makeTexture(descriptor: td, iosurface: unsafeBitCast(rtSurf, to: IOSurfaceRef.self), plane: 0)!

func frame(_ r: Float) -> Double {
    let t0 = CACurrentMediaTime()
    // 1. GL renders the "scene"
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
    glClearColor(r, 0.5, 0.25, 1); glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    glFlush()
    // 2. Metal processes it
    let cb = queue.makeCommandBuffer()!
    let ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(pso); ce.setTexture(mScene, index: 0); ce.setTexture(mRT, index: 1)
    ce.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    ce.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    // 3. GL composites the result
    glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), fboRead)
    glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), fbo2)
    glBlitFramebuffer(0, 0, GLsizei(W), GLsizei(H), 0, 0, GLsizei(W), GLsizei(H), GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
    glFinish()
    return (CACurrentMediaTime() - t0) * 1000
}
var times: [Double] = []
for i in 0..<120 { times.append(frame(Float(i % 2))) }
times.removeFirst(20); times.sort()
print(String(format: "round trip per frame: median %.2f ms, best %.2f ms, p90 %.2f ms", times[times.count/2], times[0], times[Int(Double(times.count)*0.9)]))
// verify data flow: read back a pixel from the composite
glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), fbo2)
var px = [UInt8](repeating: 0, count: 4)
glReadPixels(10, 10, 1, 1, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), &px)
print("composite pixel (B,G,R,A):", px, "expected inverted of last clear (r=1,g=.5,b=.25) -> R=0,G=127,B=191")
