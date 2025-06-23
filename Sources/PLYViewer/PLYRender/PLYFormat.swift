//
//  PLYFormat.swift
//  PLYViewer
//
//  Created by 우영학 on 6/20/25.
//

struct PLYVertex {
  var position: SIMD3<Float>
  var color: SIMD3<Float>
}

enum PLYFormat: String {
  case ascii
  case binaryLittleEndian
  case binaryBigEndian
  case unknown
}

struct PLYHeaderInfo {
  let format: PLYFormat
  let vertexCount: Int
  let vertexProperties: [PLYProperty]
  let headerLength: Int
}

struct PLYProperty {
  let type: String
  let name: String
}
