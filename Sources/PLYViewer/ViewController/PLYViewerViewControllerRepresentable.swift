//
//  PLYViewerViewControllerRepresentable.swift
//  PLYViewer
//
//  Created by 우영학 on 6/20/25.
//

import SwiftUI

struct PLYViewerViewControllerRepresentable: UIViewControllerRepresentable {
  
  func makeUIViewController(context: Context) -> some UIViewController {
    let viewController = PLYViewerViewController.make()
    return viewController
  }
  
  func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}
