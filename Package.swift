// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PLYViewer",
  platforms: [.iOS(.v16)],
  products: [
    .library(
      name: "PLYViewer",
      targets: ["PLYViewer"]),
  ],
  targets: [
    .target(
      name: "PLYViewer",
      resources: [
        .process("Metal")
      ]
    ),
  ]
)
