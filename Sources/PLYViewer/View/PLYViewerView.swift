//
//  PLYViewerView.swift
//  PLYViewer
//
//  Created by 우영학 on 6/20/25.
//

import MetalKit
import UIKit

class PLYViewerView: UIView {
  
  // MARK: - Views
  
  private(set) lazy var mtkView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
  
  // MARK: - Initializer
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupViews()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private extension PLYViewerView {
  func setupViews() {
    addSubview(mtkView)
    
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.depthStencilPixelFormat = .invalid
    mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    
    mtkView.translatesAutoresizingMaskIntoConstraints = false
    mtkView.topAnchor.constraint(equalTo: topAnchor, constant: 0).isActive = true
    mtkView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0).isActive = true
    mtkView.leftAnchor.constraint(equalTo: leftAnchor, constant: 0).isActive = true
    mtkView.rightAnchor.constraint(equalTo: rightAnchor, constant: 0).isActive = true
  }
}
