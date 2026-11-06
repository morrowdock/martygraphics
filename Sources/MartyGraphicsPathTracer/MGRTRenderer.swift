// SPDX-License-Identifier: Apache-2.0
#if canImport(Metal)
import Metal
import CoreGraphics
import Foundation
import simd

/// Progressive GPU path tracer built on Metal ray tracing (`MTLAccelerationStructure` +
/// `intersector` in a compute kernel). Works on GPUs without ray-tracing cores, such as Apple M1.
///
/// Build once per scene; `render` can then be called per frame with new instance transforms and
/// a new camera. Only the small instance acceleration structure is rebuilt per frame.
public final class MGRTRenderer {
    public enum RenderError: Error, CustomStringConvertible {
        case noDevice, noRayTracing, shader(String), resource(String)
        public var description: String {
            switch self {
            case .noDevice: return "No Metal device"
            case .noRayTracing: return "This Metal device does not support ray tracing"
            case let .shader(log): return "Shader compile failed: \(log)"
            case let .resource(what): return "Could not allocate \(what)"
            }
        }
    }

    public struct Stats: Sendable, Equatable {
        public var width: Int
        public var height: Int
        public var samplesPerPixel: Int
        /// GPU time spent in the path-tracing kernel (sum of command buffers).
        public var traceMilliseconds: Double
        /// GPU time for acceleration-structure rebuild, denoise and display passes.
        public var postMilliseconds: Double
        /// Host wall-clock time for the whole `render` call.
        public var wallMilliseconds: Double
        public var triangles: Int
        public var instances: Int
    }

    public struct Output: Sendable {
        public let width: Int
        public let height: Int
        /// Tonemapped sRGB, 8 bits per channel, RGBA, row-major top to bottom.
        public let rgba8: [UInt8]
        /// Linear HDR radiance after denoise and exposure, before glare and tonemap
        /// (only when `MGRTSettings.returnLinear` is set).
        public let linear: [SIMD4<Float>]
        public let stats: Stats

        public func cgImage() -> CGImage? {
            let data = Data(rgba8) as CFData
            guard let provider = CGDataProvider(data: data),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    /// True when a Metal device with ray-tracing support is present.
    public static var isSupported: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsRaytracing
    }

    public let device: MTLDevice
    public private(set) var scene: MGRTScene
    private let queue: MTLCommandQueue
    private let tracePipeline: MTLComputePipelineState
    private let resolvePipeline: MTLComputePipelineState
    private let atrousPipeline: MTLComputePipelineState
    private let composePipeline: MTLComputePipelineState
    private let blurPipeline: MTLComputePipelineState
    private let tonemapPipeline: MTLComputePipelineState

    private let positions: MTLBuffer
    private let normals: MTLBuffer
    private let tangents: MTLBuffer
    private let indices: MTLBuffer
    private let triMaterials: MTLBuffer
    private let materials: MTLBuffer
    private let lights: MTLBuffer
    private let envTexture: MTLTexture
    private let envMarginal: MTLBuffer
    private let envConditional: MTLBuffer
    private let envPdf: MTLBuffer
    private let pEnv: Float
    private var meshOffsets: [(vertex: UInt32, triangle: UInt32)] = []
    private var primitiveStructures: [MTLAccelerationStructure] = []
    private let instanceDescriptors: MTLBuffer
    private let instanceData: MTLBuffer
    private var instanceStructure: MTLAccelerationStructure
    private var instanceScratch: MTLBuffer
    private let instanceASDescriptor: MTLInstanceAccelerationStructureDescriptor
    public let triangleCount: Int

    private var frameBuffers: [MTLBuffer] = []
    private var frameSize = (0, 0)

    public init(scene: MGRTScene, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else { throw RenderError.noDevice }
        guard device.supportsRaytracing else { throw RenderError.noRayTracing }
        try scene.validate()
        self.device = device
        self.scene = scene
        guard let queue = device.makeCommandQueue() else { throw RenderError.resource("command queue") }
        self.queue = queue

        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        if #available(macOS 15.0, iOS 18.0, *) { options.mathMode = .relaxed }
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: MGRTShaderSource.source, options: options) } catch {
            throw RenderError.shader(String(describing: error))
        }
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw RenderError.shader("missing \(name)") }
            return try device.makeComputePipelineState(function: fn)
        }
        tracePipeline = try pipeline("pathtrace")
        resolvePipeline = try pipeline("resolve")
        atrousPipeline = try pipeline("atrous")
        composePipeline = try pipeline("compose")
        blurPipeline = try pipeline("glare_blur")
        tonemapPipeline = try pipeline("tonemap")

        // Geometry: concatenate meshes; indices stay mesh-local.
        var pos: [SIMD3<Float>] = [], nrm: [SIMD4<Float>] = [], tan: [SIMD4<Float>] = [], idx: [UInt32] = [], mat: [UInt32] = []
        var offsets: [(UInt32, UInt32)] = []
        for mesh in scene.meshes {
            offsets.append((UInt32(pos.count), UInt32(idx.count / 3)))
            pos += mesh.positions
            nrm += mesh.normals.map { SIMD4($0, 0) }
            tan += mesh.tangents.isEmpty ? Array(repeating: .zero, count: mesh.positions.count) : mesh.tangents.map { SIMD4($0, 0) }
            idx += mesh.indices
            mat += mesh.materialIDs
        }
        meshOffsets = offsets.map { (vertex: $0.0, triangle: $0.1) }
        triangleCount = idx.count / 3
        func buffer<T>(_ array: [T], _ label: String) throws -> MTLBuffer {
            let length = max(MemoryLayout<T>.stride * array.count, 16)
            let b: MTLBuffer? = array.isEmpty ? device.makeBuffer(length: length, options: .storageModeShared)
                : array.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            guard let b else { throw RenderError.resource(label) }
            b.label = label
            return b
        }
        positions = try buffer(pos, "positions")
        normals = try buffer(nrm, "normals")
        tangents = try buffer(tan, "tangents")
        indices = try buffer(idx, "indices")
        triMaterials = try buffer(mat, "triangle materials")
        materials = try buffer(scene.materials.flatMap(\.packed), "materials")

        let totalPower = scene.areaLights.reduce(Float(0)) { $0 + $1.power }
        let lightRows: [SIMD4<Float>] = scene.areaLights.flatMap { l -> [SIMD4<Float>] in
            [SIMD4(l.corner, totalPower > 0 ? l.power / totalPower : 1 / Float(scene.areaLights.count)),
             SIMD4(l.edgeU, l.area), SIMD4(l.edgeV, l.visibleToCamera ? 1 : 0), SIMD4(l.radiance, 0), SIMD4(l.normal, 0)]
        }
        lights = try buffer(lightRows, "lights")

        // Environment texture (half float, bilinear) and importance-sampling tables.
        let env = scene.environment
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: env.width, height: env.height, mipmapped: false)
        texDesc.usage = .shaderRead
        texDesc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: texDesc) else { throw RenderError.resource("environment texture") }
        let halfTexels: [UInt16] = env.texels.flatMap { [MGRTSampling.halfBits($0.x), MGRTSampling.halfBits($0.y),
                                                          MGRTSampling.halfBits($0.z), 0x3C00] }
        halfTexels.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, env.width, env.height), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: env.width * 8)
        }
        envTexture = tex
        let dist = env.makeDistribution()
        envMarginal = try buffer(dist.marginalCDF, "env marginal")
        envConditional = try buffer(dist.conditionalCDF, "env conditional")
        envPdf = try buffer(dist.pdfUV, "env pdf")
        let envOn = env.intensity > 0
        pEnv = scene.areaLights.isEmpty ? (envOn ? 1 : 0) : (envOn ? 0.5 : 0)

        // Bottom-level structures, one per mesh.
        guard let build = queue.makeCommandBuffer(), let enc = build.makeAccelerationStructureCommandEncoder() else {
            throw RenderError.resource("build encoder")
        }
        var scratchKeep: [MTLBuffer] = []
        for (i, mesh) in scene.meshes.enumerated() {
            let geo = MTLAccelerationStructureTriangleGeometryDescriptor()
            geo.vertexBuffer = positions
            geo.vertexBufferOffset = Int(offsets[i].0) * MemoryLayout<SIMD3<Float>>.stride
            geo.vertexStride = MemoryLayout<SIMD3<Float>>.stride
            geo.vertexFormat = .float3
            geo.indexBuffer = indices
            geo.indexBufferOffset = Int(offsets[i].1) * 3 * MemoryLayout<UInt32>.stride
            geo.indexType = .uint32
            geo.triangleCount = mesh.triangleCount
            geo.opaque = true
            let desc = MTLPrimitiveAccelerationStructureDescriptor()
            desc.geometryDescriptors = [geo]
            let sizes = device.accelerationStructureSizes(descriptor: desc)
            guard let accel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
                  let scratch = device.makeBuffer(length: max(sizes.buildScratchBufferSize, 16), options: .storageModePrivate) else {
                throw RenderError.resource("primitive acceleration structure")
            }
            enc.build(accelerationStructure: accel, descriptor: desc, scratchBuffer: scratch, scratchBufferOffset: 0)
            primitiveStructures.append(accel)
            scratchKeep.append(scratch)
        }
        enc.endEncoding()
        build.commit()
        build.waitUntilCompleted()
        if let error = build.error { throw RenderError.resource("acceleration build: \(error)") }
        withExtendedLifetime(scratchKeep) {}

        let n = scene.instances.count
        guard let descBuf = device.makeBuffer(length: n * MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride, options: .storageModeShared),
              let dataBuf = device.makeBuffer(length: n * MemoryLayout<MGRTInstanceGPU>.stride, options: .storageModeShared) else {
            throw RenderError.resource("instance buffers")
        }
        instanceDescriptors = descBuf
        instanceData = dataBuf
        let ias = MTLInstanceAccelerationStructureDescriptor()
        ias.instancedAccelerationStructures = primitiveStructures
        ias.instanceCount = n
        ias.instanceDescriptorBuffer = descBuf
        ias.instanceDescriptorType = .default
        instanceASDescriptor = ias
        let sizes = device.accelerationStructureSizes(descriptor: ias)
        guard let ia = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let isb = device.makeBuffer(length: max(sizes.buildScratchBufferSize, 16), options: .storageModePrivate) else {
            throw RenderError.resource("instance acceleration structure")
        }
        instanceStructure = ia
        instanceScratch = isb
        writeInstances(scene.instances.map(\.transform))
    }

    private func writeInstances(_ transforms: [simd_float4x4]) {
        let descs = instanceDescriptors.contents().bindMemory(to: MTLAccelerationStructureInstanceDescriptor.self, capacity: transforms.count)
        let data = instanceData.contents().bindMemory(to: MGRTInstanceGPU.self, capacity: transforms.count)
        for (i, inst) in scene.instances.enumerated() {
            let m = transforms[i]
            func col(_ c: SIMD4<Float>) -> MTLPackedFloat3 { MTLPackedFloat3Make(c.x, c.y, c.z) }
            var d = MTLAccelerationStructureInstanceDescriptor()
            d.transformationMatrix = MTLPackedFloat4x3(columns: (col(m.columns.0), col(m.columns.1), col(m.columns.2), col(m.columns.3)))
            d.options = .opaque
            d.mask = 0xFF
            d.intersectionFunctionTableOffset = 0
            d.accelerationStructureIndex = UInt32(inst.mesh)
            descs[i] = d
            let off = meshOffsets[inst.mesh]
            data[i] = MGRTInstanceGPU(model: m, normalMatrix: m.inverse.transpose,
                                      info: SIMD4(off.vertex, off.triangle, UInt32(inst.mesh), 0))
        }
    }

    private func ensureFrameBuffers(_ w: Int, _ h: Int) throws {
        guard frameSize != (w, h) || frameBuffers.isEmpty else { return }
        frameBuffers = []
        let count = w * h
        // 0 accum, 1 aov albedo, 2 aov normal, 3 irradiance A, 4 irradiance B, 5 guide, 6 albedo, 7 hdr, 8 glare A, 9 glare B, 10 rgba8
        for i in 0..<11 {
            let length = i == 10 ? count * 4 : count * MemoryLayout<SIMD4<Float>>.stride
            guard let b = device.makeBuffer(length: length, options: i == 10 || i == 7 || i <= 2 ? .storageModeShared : .storageModePrivate) else {
                throw RenderError.resource("frame buffer \(i)")
            }
            frameBuffers.append(b)
        }
        frameSize = (w, h)
    }

    private static func gpuMilliseconds(_ cb: MTLCommandBuffer) -> Double {
        max(0, cb.gpuEndTime - cb.gpuStartTime) * 1000
    }

    /// Renders one frame. `transforms` (one per instance) and `camera` override the scene's values.
    public func render(settings: MGRTSettings, camera: MGRTCamera? = nil, transforms: [simd_float4x4]? = nil) throws -> Output {
        let start = Date()
        let w = settings.width, h = settings.height
        precondition(w > 0 && h > 0 && settings.samplesPerPixel > 0, "render size")
        try ensureFrameBuffers(w, h)
        if let transforms {
            precondition(transforms.count == scene.instances.count, "one transform per instance")
            writeInstances(transforms)
        }
        var post: Double = 0, trace: Double = 0

        // Rebuild the top-level structure and clear accumulation.
        guard let prep = queue.makeCommandBuffer(), let asEnc = prep.makeAccelerationStructureCommandEncoder() else {
            throw RenderError.resource("command buffer")
        }
        asEnc.build(accelerationStructure: instanceStructure, descriptor: instanceASDescriptor,
                    scratchBuffer: instanceScratch, scratchBufferOffset: 0)
        asEnc.endEncoding()
        if let blit = prep.makeBlitCommandEncoder() {
            for i in 0...2 { blit.fill(buffer: frameBuffers[i], range: 0..<frameBuffers[i].length, value: 0) }
            blit.endEncoding()
        }
        prep.commit()

        let cam = camera ?? scene.camera
        let basis = cam.basis
        var u = MGRTUniforms(
            camPos: SIMD4(cam.position, max(cam.apertureRadius, 0)),
            camU: SIMD4(basis.right, cam.resolvedFocusDistance),
            camV: SIMD4(basis.up, tan(cam.verticalFOVDegrees * .pi / 360)),
            camW: SIMD4(basis.forward, Float(w) / Float(h)),
            size: SIMD4(UInt32(w), UInt32(h), 0, 0),
            frame: SIMD4(0, settings.seed, UInt32(max(1, settings.maxBounces)), UInt32(scene.areaLights.count)),
            envInfo: SIMD4(UInt32(scene.environment.width), UInt32(scene.environment.height), settings.debugFlags, UInt32(scene.instances.count)),
            params: SIMD4(scene.environment.intensity, settings.clampIndirect,
                          scene.areaLights.isEmpty ? pEnv : (pEnv > 0 ? min(max(settings.environmentSelectProbability, 0.05), 0.95) : 0), 0))
        let tile = max(64, settings.tileSize)
        var pending: [MTLCommandBuffer] = [prep]
        for s in 0..<settings.samplesPerPixel {
            guard let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else {
                throw RenderError.resource("trace command buffer")
            }
            enc.setComputePipelineState(tracePipeline)
            enc.setAccelerationStructure(instanceStructure, bufferIndex: 1)
            for p in primitiveStructures { enc.useResource(p, usage: .read) }
            let bufs: [MTLBuffer] = [instanceData, positions, normals, tangents, indices, triMaterials, materials, lights,
                                     envMarginal, envConditional, envPdf, frameBuffers[0], frameBuffers[1], frameBuffers[2]]
            for (k, b) in bufs.enumerated() { enc.setBuffer(b, offset: 0, index: k + 2) }
            enc.setTexture(envTexture, index: 0)
            u.frame.x = UInt32(s)
            var ty = 0
            while ty < h {
                var tx = 0
                while tx < w {
                    u.size.z = UInt32(tx); u.size.w = UInt32(ty)
                    enc.setBytes(&u, length: MemoryLayout<MGRTUniforms>.stride, index: 0)
                    enc.dispatchThreads(MTLSize(width: min(tile, w - tx), height: min(tile, h - ty), depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
                    tx += tile
                }
                ty += tile
            }
            enc.endEncoding()
            cb.commit()
            pending.append(cb)
            // Keep at most a few submissions in flight so the display stays responsive.
            if pending.count >= 3 {
                let first = pending.removeFirst()
                first.waitUntilCompleted()
                if let error = first.error { throw RenderError.resource("trace: \(error)") }
                if first === prep { post += Self.gpuMilliseconds(first) } else { trace += Self.gpuMilliseconds(first) }
            }
        }
        for cb in pending {
            cb.waitUntilCompleted()
            if let error = cb.error { throw RenderError.resource("trace: \(error)") }
            if cb === prep { post += Self.gpuMilliseconds(cb) } else { trace += Self.gpuMilliseconds(cb) }
        }

        // Denoise, compose, glare, tonemap.
        guard let pcb = queue.makeCommandBuffer(), let enc = pcb.makeComputeCommandEncoder() else {
            throw RenderError.resource("post command buffer")
        }
        var pu = MGRTPostUniforms(size: SIMD4(UInt32(w), UInt32(h), 1, UInt32(settings.samplesPerPixel)),
                                  params: SIMD4(settings.denoiseStrength, 64, 1, settings.exposure),
                                  params2: SIMD4(settings.vignette, settings.bloom, settings.denoise ? 1 : 0, 0.35))
        let grid = MTLSize(width: w, height: h, depth: 1), group = MTLSize(width: 8, height: 8, depth: 1)
        let fb = frameBuffers
        if settings.denoise {
            enc.setComputePipelineState(resolvePipeline)
            enc.setBytes(&pu, length: MemoryLayout<MGRTPostUniforms>.stride, index: 0)
            for (k, b) in [fb[0], fb[1], fb[2], fb[3], fb[5], fb[6]].enumerated() { enc.setBuffer(b, offset: 0, index: k + 1) }
            enc.dispatchThreads(grid, threadsPerThreadgroup: group)
            enc.setComputePipelineState(atrousPipeline)
            var src = fb[3], dst = fb[4]
            for pass in 0..<5 {
                pu.size.z = UInt32(1 << pass)
                enc.setBytes(&pu, length: MemoryLayout<MGRTPostUniforms>.stride, index: 0)
                enc.setBuffer(src, offset: 0, index: 1)
                enc.setBuffer(dst, offset: 0, index: 2)
                enc.setBuffer(fb[5], offset: 0, index: 3)
                enc.setBuffer(fb[6], offset: 0, index: 4)
                enc.dispatchThreads(grid, threadsPerThreadgroup: group)
                swap(&src, &dst)
            }
            enc.setComputePipelineState(composePipeline)
            enc.setBytes(&pu, length: MemoryLayout<MGRTPostUniforms>.stride, index: 0)
            for (k, b) in [fb[0], src, fb[6], fb[7]].enumerated() { enc.setBuffer(b, offset: 0, index: k + 1) }
            enc.dispatchThreads(grid, threadsPerThreadgroup: group)
        } else {
            enc.setComputePipelineState(composePipeline)
            enc.setBytes(&pu, length: MemoryLayout<MGRTPostUniforms>.stride, index: 0)
            for (k, b) in [fb[0], fb[3], fb[6], fb[7]].enumerated() { enc.setBuffer(b, offset: 0, index: k + 1) }
            enc.dispatchThreads(grid, threadsPerThreadgroup: group)
        }
        if settings.bloom > 0 {
            let radius = Float(max(w, h)) / 160
            enc.setComputePipelineState(blurPipeline)
            for (pass, (s, d)) in [(fb[7], fb[8]), (fb[8], fb[9])].enumerated() {
                var bu = MGRTPostUniforms(size: SIMD4(UInt32(w), UInt32(h), UInt32(pass), 0),
                                          params: SIMD4(radius, pass == 0 ? 1 : 0, 0, 0), params2: .zero)
                enc.setBytes(&bu, length: MemoryLayout<MGRTPostUniforms>.stride, index: 0)
                enc.setBuffer(s, offset: 0, index: 1)
                enc.setBuffer(d, offset: 0, index: 2)
                enc.dispatchThreads(grid, threadsPerThreadgroup: group)
            }
        }
        enc.setComputePipelineState(tonemapPipeline)
        enc.setBytes(&pu, length: MemoryLayout<MGRTPostUniforms>.stride, index: 0)
        for (k, b) in [fb[7], fb[9], fb[10]].enumerated() { enc.setBuffer(b, offset: 0, index: k + 1) }
        enc.dispatchThreads(grid, threadsPerThreadgroup: group)
        enc.endEncoding()
        pcb.commit()
        pcb.waitUntilCompleted()
        if let error = pcb.error { throw RenderError.resource("post: \(error)") }
        post += Self.gpuMilliseconds(pcb)

        let ptr = fb[10].contents().bindMemory(to: UInt8.self, capacity: w * h * 4)
        let bytes = Array(UnsafeBufferPointer(start: ptr, count: w * h * 4))
        let stats = Stats(width: w, height: h, samplesPerPixel: settings.samplesPerPixel, traceMilliseconds: trace,
                          postMilliseconds: post, wallMilliseconds: Date().timeIntervalSince(start) * 1000,
                          triangles: triangleCount, instances: scene.instances.count)
        var linear: [SIMD4<Float>] = []
        if settings.returnLinear {
            let hp = fb[7].contents().bindMemory(to: SIMD4<Float>.self, capacity: w * h)
            linear = Array(UnsafeBufferPointer(start: hp, count: w * h))
        }
        return Output(width: w, height: h, rgba8: bytes, linear: linear, stats: stats)
    }
}

struct MGRTUniforms {
    var camPos: SIMD4<Float>
    var camU: SIMD4<Float>
    var camV: SIMD4<Float>
    var camW: SIMD4<Float>
    var size: SIMD4<UInt32>
    var frame: SIMD4<UInt32>
    var envInfo: SIMD4<UInt32>
    var params: SIMD4<Float>
}

struct MGRTPostUniforms {
    var size: SIMD4<UInt32>
    var params: SIMD4<Float>
    var params2: SIMD4<Float>
}

struct MGRTInstanceGPU {
    var model: simd_float4x4
    var normalMatrix: simd_float4x4
    var info: SIMD4<UInt32>
}
#endif
