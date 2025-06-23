//
//  PLYViewerViewControllerRepresentable.swift
//  PLYViewer
//
//  Created by 우영학 on 6/20/25.
//

import SwiftUI

public struct PLYViewerViewControllerRepresentable: UIViewControllerRepresentable {
  let url: URL
  
  public init(url: URL) {
    self.url = url
  }
  
  public func makeUIViewController(context: Context) -> some UIViewController {
    let viewController = PLYViewerViewController.make(url: url)
    return viewController
  }
  
  public func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}
