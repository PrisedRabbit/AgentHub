//
//  MermaidRenderHelper.swift
//  AgentHub
//
//  Thin wrapper that isolates the BeautifulMermaid import so its `State` type
//  doesn't pollute SwiftUI view files and cause @State ambiguity.
//

import AppKit
import BeautifulMermaid

enum MermaidRenderHelper {
  /// Renders a Mermaid diagram source string to an NSImage.
  static func renderImage(source: String) throws -> NSImage? {
    try MermaidRenderer.renderImage(source: source)
  }
}
