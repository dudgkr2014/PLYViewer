//
//  PLYViewerViewController.swift
//  PLYViewer
//
//  Created by 우영학 on 6/20/25.
//

import MetalKit
import UIKit

class PLYViewerViewController: UIViewController {
  
  // MARK: - Render
  
  private let renderer: PLYRender
  
  // MARK: - View
  
  private let viewerView: PLYViewerView
  
  // MARK: - Initializer
  
  private init(url: URL) {
    viewerView = PLYViewerView()
    renderer = PLYRender(mtkView: viewerView.mtkView, url: url)
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: - Life Cycles
  
  override func loadView() {
    self.view = viewerView
  }
  
  override func viewDidLoad() {
    addGesture()
  }
  
  func addGesture() {
    let panGesture = UIPanGestureRecognizer(target: renderer, action: #selector(renderer.handlePan(_:)))
    viewerView.mtkView.addGestureRecognizer(panGesture)
  }
  
  // MARK: - Factory
  
  public static func make(url: URL) -> PLYViewerViewController {
    let viewController = PLYViewerViewController(url: url)
    return viewController
  }
}
