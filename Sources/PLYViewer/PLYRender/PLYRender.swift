//
//  PLYRender.swift
//  PLYViewer
//
//  Created by 우영학 on 6/20/25.
//

import Foundation
@preconcurrency import MetalKit
import simd

@MainActor
public class PLYRender: NSObject {
  
  // MARK: - Properties
  
  private let mtkView: MTKView
  private var plyVertices: [PLYVertex] = []
  private var indexBuffer: MTLBuffer?
  private var indexCount: Int = 0
  
  // MARK: - Gesture
  
  private var lastDistance: CGFloat?
  private(set) var orbitRotation: SIMD2<Float> = SIMD2<Float>(0, 0)
  
  private(set) var cameraDistance: Float = 1.5
  private(set) var cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
  
  var cameraPosition: SIMD3<Float> {
    let x = cameraDistance * cos(orbitRotation.y) * sin(orbitRotation.x)
    let y = cameraDistance * sin(orbitRotation.y)
    let z = cameraDistance * cos(orbitRotation.y) * cos(orbitRotation.x)
    return cameraTarget + SIMD3<Float>(x, y, z)
  }
  
  // MARK: - Metal Pipeline
  
  private var commandQueue: MTLCommandQueue?
  private var pipelineState: MTLRenderPipelineState?
  
  // MARK: - Metal Buffer
  
  private var vertexBuffer: MTLBuffer?
  
  // MARK: - Intializer
  
  public init(mtkView: MTKView, url: URL) {
    self.mtkView = mtkView
    self.commandQueue = mtkView.device?.makeCommandQueue()
    super.init()
    
    mtkView.colorPixelFormat = .bgra8Unorm
    
    mtkView.delegate = self
    
    makePipelineState(url: url)
  }
  
  private func makePipelineState(url: URL) {
    guard let device = mtkView.device else { return }
    
    let metallibURL = Bundle.module.url(forResource: "default", withExtension: "metallib")!
    let library = try? device.makeLibrary(URL: metallibURL)
    
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    vertexDescriptor.attributes[1].format = .float3
    vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
    vertexDescriptor.attributes[1].bufferIndex = 0
    
    vertexDescriptor.layouts[0].stride = MemoryLayout<PLYVertex>.stride
    vertexDescriptor.layouts[0].stepRate = 1
    vertexDescriptor.layouts[0].stepFunction = .perVertex
    
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = library?.makeFunction(name: "vertex_main")
    pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "fragment_main")
    pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
    pipelineDescriptor.vertexDescriptor = vertexDescriptor
    
    do {
      pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      Task {
        guard let (vertexData, indexData) = parsePLYVerticesAndFaces(from: url) else { return }
        
        plyVertices = vertexData
        vertexBuffer = mtkView.device?.makeBuffer(
          bytes: vertexData,
          length: MemoryLayout<PLYVertex>.stride * vertexData.count,
          options: .storageModeShared
        )
        
        if indexData.count != 0 {
          indexBuffer = mtkView.device?.makeBuffer(
            bytes: indexData,
            length: MemoryLayout<UInt32>.stride * indexData.count,
            options: .storageModeShared
          )
          indexCount = indexData.count
        }
        
        mtkView.draw()
      }
    } catch {
      print("PipelineState 생성 실패: \(error)")
    }
  }
  
  func parsePLYHeader(from url: URL) -> PLYHeaderInfo? {
    guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? fileHandle.close() }
    
    let headerGuessSize = 4096
    let headerData = fileHandle.readData(ofLength: headerGuessSize)
    
    guard let headerString = String(data: headerData, encoding: .ascii) else { return nil }
    
    let lines = headerString.components(separatedBy: .newlines)
    
    var format: PLYFormat = .unknown
    var vertexCount: Int?
    var vertexProperties: [PLYProperty] = []
    var isVertexSection = false
    var headerLength = 0
    
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      headerLength += line.lengthOfBytes(using: .ascii) + 1  // +1 for newline
      
      if trimmed == "end_header" {
        break
      }
      
      if trimmed.starts(with: "format") {
        if trimmed.contains("ascii") {
          format = .ascii
        } else if trimmed.contains("binary_little_endian") {
          format = .binaryLittleEndian
        } else if trimmed.contains("binary_big_endian") {
          format = .binaryBigEndian
        }
      } else if trimmed.starts(with: "element vertex") {
        let comps = trimmed.split(separator: " ")
        if comps.count == 3, let count = Int(comps[2]) {
          vertexCount = count
          isVertexSection = true
        }
      } else if trimmed.starts(with: "element") {
        isVertexSection = false
      } else if isVertexSection && trimmed.starts(with: "property") {
        let comps = trimmed.split(separator: " ")
        if comps.count == 3 {
          vertexProperties.append(PLYProperty(
            type: String(comps[1]),
            name: String(comps[2])
          ))
        }
      }
    }
    
    guard let count = vertexCount else { return nil }
    
    return PLYHeaderInfo(
      format: format,
      vertexCount: count,
      vertexProperties: vertexProperties,
      headerLength: headerLength
    )
  }
  
  func loadPLYDataSafely(from url: URL) -> (headerText: String, rawData: Data)? {
    guard let fullData = try? Data(contentsOf: url) else { return nil }
    guard let headerEndRange = fullData.range(of: Data("end_header\n".utf8)) else { return nil }
    
    let headerEndIndex = headerEndRange.upperBound
    let headerData = fullData.subdata(in: 0..<headerEndIndex)
    
    guard let headerText = String(data: headerData, encoding: .ascii) else { return nil }
    
    let bodyData = fullData.suffix(from: headerEndIndex)
    
    return (headerText, bodyData)
  }
  
  func parsePLYVertices(from url: URL) -> [PLYVertex]? {
    guard let header = parsePLYHeader(from: url) else { return nil }
    guard let data = try? String(contentsOf: url, encoding: .utf8) else { return nil }
     
    let lines = data.components(separatedBy: .newlines)
    guard let headerEndIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "end_header" }) else {
      return nil
    }
    
    let vertexLines = lines[(headerEndIndex + 1)..<(headerEndIndex + 1 + header.vertexCount)]
    
    let properties = header.vertexProperties
    
    let vertices: [PLYVertex] = vertexLines.compactMap { line in
      let comps = line.split(separator: " ")
      guard comps.count >= properties.count else { return nil }
      
      var position = SIMD3<Float>(0, 0, 0)
      var color = SIMD3<Float>(255, 255, 255)
      
      for (i, prop) in properties.enumerated() {
        switch prop.name {
        case "x": position.x = Float(comps[i]) ?? 0
        case "y": position.y = Float(comps[i]) ?? 0
        case "z": position.z = Float(comps[i]) ?? 0
        case "red": color.x = Float(comps[i]) ?? 255
        case "green": color.y = Float(comps[i]) ?? 255
        case "blue": color.z = Float(comps[i]) ?? 255
        default: continue
        }
      }
      
      return PLYVertex(position: position, color: color)
    }
    
    return vertices
  }
  
  func parsePLYVerticesAndFaces(from url: URL) -> ([PLYVertex], [UInt32])? {
    guard let header = parsePLYHeader(from: url) else { return nil }
    guard let data = try? String(contentsOf: url, encoding: .utf8) else { return nil }

    let lines = data.components(separatedBy: .newlines)
    guard let headerEndIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "end_header" }) else {
      return nil
    }

    let vertexLines = lines[(headerEndIndex + 1)..<(headerEndIndex + 1 + header.vertexCount)]
    let faceLines = lines.dropFirst(headerEndIndex + 1 + header.vertexCount)

    let properties = header.vertexProperties

    let vertices: [PLYVertex] = vertexLines.compactMap { line in
      let comps = line.split(separator: " ")
      guard comps.count >= properties.count else { return nil }

      var position = SIMD3<Float>(0, 0, 0)
      var color = SIMD3<Float>(255, 255, 255)

      for (i, prop) in properties.enumerated() {
        switch prop.name {
        case "x": position.x = Float(comps[i]) ?? 0
        case "y": position.y = Float(comps[i]) ?? 0
        case "z": position.z = Float(comps[i]) ?? 0
        case "red": color.x = Float(comps[i]) ?? 255
        case "green": color.y = Float(comps[i]) ?? 255
        case "blue": color.z = Float(comps[i]) ?? 255
        default: continue
        }
      }

      return PLYVertex(position: position, color: color)
    }

    let allFaceIndices: [[UInt32]] = faceLines.compactMap { line in
      let comps = line.split(separator: " ").compactMap { Int($0) }
      guard comps.count >= 4 else { return nil }

      let count = comps[0]
      let faceIndices = comps.dropFirst()

      if count == 3 {
        return faceIndices.prefix(3).map { UInt32($0) }
      } else if count >= 4 {
        var result: [UInt32] = []
        let base = UInt32(faceIndices[0])
        for i in 1..<(count - 1) {
          result.append(base)
          result.append(UInt32(faceIndices[i]))
          result.append(UInt32(faceIndices[i + 1]))
        }
        print("Wyh \(result)")
        return result
      } else {
        return nil
      }
    }

    let indices: [UInt32] = allFaceIndices.flatMap { $0 }

    return (vertices, indices)
  }

}

// MARK: - Supports

extension PLYRender {
  func readLines(from fileURL: URL) throws -> [String] {
    var lines: [String] = []
    
    let fileHandle = try FileHandle(forReadingFrom: fileURL)
    defer { try? fileHandle.close() }
    
    let buffer = fileHandle.readDataToEndOfFile()
    
    if let content = String(data: buffer, encoding: .utf8) {
      content.enumerateLines { line, _ in
        lines.append(line)
      }
    } else {
      throw NSError(domain: "PLYReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "파일 인코딩 실패"])
    }
    
    return lines
  }
}

extension PLYRender: MTKViewDelegate {
  // swiftlint:disable:next function_body_length
  public func draw(in view: MTKView) {
    guard let drawable = view.currentDrawable,
          let renderPassDescriptor = view.currentRenderPassDescriptor,
          let commandBuffer = commandQueue?.makeCommandBuffer(),
          let pipelineState = pipelineState,
          let vertexBuffer = vertexBuffer else { return }
    
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    let bounds = plyVertices.reduce(
      (min: SIMD3<Float>(repeating: .greatestFiniteMagnitude), max: SIMD3<Float>(repeating: -.greatestFiniteMagnitude))
    ) { result, vtx in
      (
        min: simd_min(result.min, vtx.position),
        max: simd_max(result.max, vtx.position)
      )
    }
    
    let center = bounds.min + bounds.max
    let scale: Float = 1.0 / max(
      bounds.max.x - bounds.min.x,
      bounds.max.y - bounds.min.y,
      bounds.max.z - bounds.min.z
    )
    let aspect = Float(mtkView.drawableSize.width / mtkView.drawableSize.height)
    let viewMatrix = lookAt(eye: cameraPosition, center: cameraTarget, up: SIMD3<Float>(0, 1, 0))
    let projMatrix = perspective(fovY: .pi / 3, aspect: aspect, near: 0.01, far: 100.0)
    let mvp = projMatrix * viewMatrix
    
    var uniforms = Uniforms(center: center, scale: scale, mvp: mvp)
    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    if let indexBuffer = indexBuffer, indexCount > 0 {
      renderEncoder.drawIndexedPrimitives(
        type: .triangle,
        indexCount: indexCount,
        indexType: .uint32,
        indexBuffer: indexBuffer,
        indexBufferOffset: 0
      )
    } else {
      renderEncoder.drawPrimitives(
        type: .point,
        vertexStart: 0,
        vertexCount: plyVertices.count
      )
    }
    renderEncoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

// MARK: - Update View Pose

extension PLYRender {
  func updateRotation(x: Float, y: Float) {
    let sensitivity: Float = 1
    orbitRotation.x -= x * sensitivity
    orbitRotation.y += y * sensitivity
    
    let maxElevation = Float.pi / 2 - 0.01
    orbitRotation.y = max(-maxElevation, min(maxElevation, orbitRotation.y))
    mtkView.draw()
  }
  
  func updatePosition(x: Float, y: Float, z: Float) {
    let forward = normalize(cameraTarget - cameraPosition)
    let right = normalize(cross(SIMD3<Float>(0, 1, 0), forward))
    let up = cross(forward, right)
    
    let panMovement = right * x + up * y
    cameraTarget += panMovement
    cameraDistance = max(0.5, cameraDistance + z)
    mtkView.draw()
  }
}

// MARK: - Gesture

public extension PLYRender {
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: mtkView)
    let deltaX = Float(translation.x)
    let deltaY = Float(translation.y)
    let sensitivity: Float = 0.005
    
    switch gesture.state {
    case .began:
      if gesture.numberOfTouches == 2 {
        let p0 = gesture.location(ofTouch: 0, in: mtkView)
        let p1 = gesture.location(ofTouch: 1, in: mtkView)
        lastDistance = hypot(p1.x - p0.x, p1.y - p0.y)
      }
      
    case .changed:
      switch gesture.numberOfTouches {
      case 1:
        updateRotation(x: deltaX * sensitivity, y: deltaY * sensitivity)
        gesture.setTranslation(.zero, in: mtkView)
        
      case 2:
        let p0 = gesture.location(ofTouch: 0, in: mtkView)
        let p1 = gesture.location(ofTouch: 1, in: mtkView)
        let currentDistance = hypot(p1.x - p0.x, p1.y - p0.y)
        if let last = lastDistance {
          let deltaDistance = currentDistance - last
          let signedScaleDelta = Float(deltaDistance) * sensitivity
          updatePosition(
            x: deltaX * sensitivity,
            y: deltaY * sensitivity,
            z: -signedScaleDelta
          )
        }
        lastDistance = currentDistance
        gesture.setTranslation(.zero, in: mtkView)
        
      default:
        break
      }
      
    case .ended, .cancelled, .failed:
      lastDistance = nil
      
    default:
      break
    }
  }
}

// MARK: - MVP

extension PLYRender {
  func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let f = normalize(center - eye)
    let r = normalize(cross(f, up))
    let u = cross(r, f)
    
    let rotation = simd_float4x4(columns: (
      SIMD4<Float>(r.x, u.x, -f.x, 0),
      SIMD4<Float>(r.y, u.y, -f.y, 0),
      SIMD4<Float>(r.z, u.z, -f.z, 0),
      SIMD4<Float>(0, 0, 0, 1)
    ))
    
    let translation = simd_float4x4(translation: -eye)
    return rotation * translation
  }
  
  func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let yScale = 1 / tan(fovY * 0.5)
    let xScale = yScale / aspect
    let zRange = far - near
    let zScale = -(far + near) / zRange
    let wzScale = -2 * far * near / zRange
    
    return simd_float4x4(columns: (
      SIMD4<Float>(xScale, 0, 0, 0),
      SIMD4<Float>(0, yScale, 0, 0),
      SIMD4<Float>(0, 0, zScale, -1),
      SIMD4<Float>(0, 0, wzScale, 0)
    ))
  }
  
}

struct Uniforms {
  var center: SIMD3<Float>
  var scale: Float
  var mvp: simd_float4x4
}

extension simd_float4x4 {
  init(translation: SIMD3<Float>) {
    self = matrix_identity_float4x4
    columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
  }
}
