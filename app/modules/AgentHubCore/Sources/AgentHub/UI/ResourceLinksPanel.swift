//
//  ResourceLinksPanel.swift
//  AgentHub
//
//  Created by Assistant on 3/11/26.
//

import SwiftUI

// MARK: - ResourceLinksPanel

/// A compact bottom panel that displays clickable resource links detected in session responses
struct ResourceLinksPanel: View {
  let links: [ResourceLink]
  let providerKind: SessionProviderKind
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()

      // Header bar - always visible, toggles expand/collapse
      Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
        HStack(spacing: 6) {
          Image(systemName: "link")
            .font(.caption2)
            .foregroundColor(.brandPrimary(for: providerKind))

          Text("Resources")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.primary)

          Text("\(links.count)")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())

          Spacer()

          Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isExpanded {
        Divider()

        // Scrollable link list
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(links) { link in
              ResourceLinkChip(link: link, providerKind: providerKind)
            }
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
        }
      }
    }
    .background(Color.primary.opacity(0.03))
  }
}

// MARK: - ResourceLinkChip

/// A compact clickable chip for a single resource link
private struct ResourceLinkChip: View {
  let link: ResourceLink
  let providerKind: SessionProviderKind
  @State private var isHovering = false

  var body: some View {
    Button(action: openLink) {
      HStack(spacing: 4) {
        Image(systemName: iconForURL(link.url))
          .font(.caption2)

        VStack(alignment: .leading, spacing: 0) {
          Text(link.displayTitle)
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(1)
          Text(link.displayDomain)
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        isHovering
          ? Color.brandPrimary(for: providerKind).opacity(0.12)
          : Color.secondary.opacity(0.08)
      )
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in isHovering = hovering }
    .help(link.url)
  }

  private func openLink() {
    guard let url = URL(string: link.url) else { return }
    NSWorkspace.shared.open(url)
  }

  private func iconForURL(_ urlString: String) -> String {
    let lowered = urlString.lowercased()
    if lowered.contains("github.com") {
      return "curlybraces"
    } else if lowered.contains("docs.") || lowered.contains("documentation") {
      return "doc.text"
    } else if lowered.contains("stackoverflow.com") {
      return "questionmark.circle"
    } else if lowered.contains("npm") || lowered.contains("pypi") || lowered.contains("crates.io") {
      return "shippingbox"
    } else {
      return "globe"
    }
  }
}

// MARK: - Preview

#Preview {
  VStack {
    ResourceLinksPanel(
      links: [
        ResourceLink(url: "https://github.com/anthropics/claude-code/issues/123"),
        ResourceLink(url: "https://docs.swift.org/swift-book/documentation/the-swift-programming-language"),
        ResourceLink(url: "https://stackoverflow.com/questions/12345/some-question"),
        ResourceLink(url: "https://example.com/api/v2/endpoint"),
      ],
      providerKind: .claude
    )
  }
  .frame(width: 400)
}
