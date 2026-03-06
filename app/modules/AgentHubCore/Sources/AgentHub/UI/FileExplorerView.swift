//
//  FileExplorerView.swift
//  AgentHub
//
//  Full-screen file explorer with a tree sidebar and an editable code editor panel.
//  Mirrors the GitDiffView layout: header / sidebar / main panel.
//

import SwiftUI
import AppKit
import CodeEditTextView

// MARK: - FileExplorerView

/// A panel that lets the user browse and edit files in a project directory.
///
/// - Shows a hierarchical file tree in a collapsible sidebar (240 pt wide).
/// - Opens files in a ``CETextViewRepresentable`` editor backed by ``CodeEditTextView/TextView``.
/// - Tracks unsaved changes and prompts before closing.
public struct FileExplorerView: View {

  // MARK: - Properties

  let session: CLISession
  let projectPath: String
  let onDismiss: () -> Void
  let isEmbedded: Bool
  let initialFilePath: String?

  // MARK: - State

  @State private var treeNodes: [FileTreeNode] = []
  @State private var isLoading = true
  @State private var selectedFilePath: String?
  @State private var fileContent: String = ""
  @State private var isLoadingFile = false
  @State private var fileError: String?
  @State private var hasUnsavedChanges = false
  @State private var isSaving = false
  @State private var showSidebar = true
  @State private var showDiscardAlert = false
  @State private var expandedPaths: Set<String> = []

  // MARK: - Init

  public init(
    session: CLISession,
    projectPath: String,
    onDismiss: @escaping () -> Void,
    isEmbedded: Bool = false,
    initialFilePath: String? = nil
  ) {
    self.session = session
    self.projectPath = projectPath
    self.onDismiss = onDismiss
    self.isEmbedded = isEmbedded
    self.initialFilePath = initialFilePath
  }

  // MARK: - Body

  public var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      if isLoading {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading files…")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(spacing: 0) {
          if showSidebar {
            fileTreeSidebar
              .frame(width: 240)
            Divider()
          }
          fileContentArea
        }
        .animation(.easeInOut(duration: 0.25), value: showSidebar)
      }
    }
    .frame(
      minWidth: isEmbedded ? 400 : 1000,
      idealWidth: isEmbedded ? 600 : 1200,
      maxWidth: .infinity,
      minHeight: isEmbedded ? 400 : 500,
      idealHeight: isEmbedded ? 600 : 750,
      maxHeight: .infinity
    )
    .task {
      await loadFileTree()
      if let initial = initialFilePath {
        await openFile(at: initial)
        expandToFile(initial)
      }
    }
    .onKeyPress(.escape) {
      if hasUnsavedChanges {
        showDiscardAlert = true
        return .handled
      }
      onDismiss()
      return .handled
    }
    .confirmationDialog(
      "Unsaved Changes",
      isPresented: $showDiscardAlert,
      titleVisibility: .visible
    ) {
      Button("Discard Changes", role: .destructive) {
        hasUnsavedChanges = false
        onDismiss()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You have unsaved changes. Close anyway?")
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 8) {
      // Sidebar toggle
      Button {
        showSidebar.toggle()
      } label: {
        Image(systemName: "sidebar.left")
          .font(.system(size: 14))
          .foregroundStyle(showSidebar ? .primary : .secondary)
      }
      .buttonStyle(.plain)
      .help(showSidebar ? "Hide file tree" : "Show file tree")

      // Divider
      Rectangle()
        .fill(Color.secondary.opacity(0.3))
        .frame(width: 1, height: 16)

      // File path breadcrumb or project name
      if let path = selectedFilePath {
        let relPath = path.hasPrefix(projectPath + "/")
          ? String(path.dropFirst(projectPath.count + 1))
          : (path as NSString).lastPathComponent
        HStack(spacing: 4) {
          Text(relPath)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
          if hasUnsavedChanges {
            Circle()
              .fill(Color.orange)
              .frame(width: 6, height: 6)
          }
        }
      } else {
        Text(URL(fileURLWithPath: projectPath).lastPathComponent)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
      }

      Spacer()

      // Save button
      if selectedFilePath != nil && hasUnsavedChanges {
        Button("Save") {
          saveCurrentFile()
        }
        .keyboardShortcut("s", modifiers: .command)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isSaving)
      }

      // Close button
      if !isEmbedded {
        Button {
          if hasUnsavedChanges {
            showDiscardAlert = true
          } else {
            onDismiss()
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .help("Close")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.surfaceElevated)
  }

  // MARK: - File Tree Sidebar

  private var fileTreeSidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Files")
          .font(.system(size: 13, weight: .bold, design: .monospaced))
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)

      Divider()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(treeNodes) { node in
            FileTreeNodeView(
              node: node,
              depth: 0,
              selectedFilePath: $selectedFilePath,
              expandedPaths: $expandedPaths,
              onSelectFile: { path in
                Task { await openFile(at: path) }
              }
            )
          }
        }
        .padding(8)
      }
    }
  }

  // MARK: - File Content Area

  @ViewBuilder
  private var fileContentArea: some View {
    if let error = fileError {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
          .font(.system(size: 36))
          .foregroundColor(.red.opacity(0.6))
        Text("Cannot display file")
          .font(.headline)
          .foregroundColor(.secondary)
        Text(error)
          .font(.caption)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding()
    } else if isLoadingFile {
      VStack(spacing: 12) {
        ProgressView()
        Text("Loading file…")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if selectedFilePath == nil {
      VStack(spacing: 8) {
        Image(systemName: "doc.text.magnifyingglass")
          .font(.system(size: 40))
          .foregroundColor(.secondary.opacity(0.4))
        Text("Select a file to view")
          .font(.callout)
          .foregroundColor(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      CETextViewRepresentable(
        text: $fileContent,
        onTextChange: { hasUnsavedChanges = true }
      )
    }
  }

  // MARK: - Actions

  private func loadFileTree() async {
    isLoading = true
    treeNodes = await FileIndexService.shared.index(projectPath: projectPath)
    isLoading = false
  }

  private func openFile(at path: String) async {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    let binaryExts: Set<String> = [
      "png", "jpg", "jpeg", "gif", "pdf", "zip", "tar", "gz",
      "exe", "dylib", "a", "o", "mp3", "mp4", "mov", "woff", "ttf"
    ]
    guard !binaryExts.contains(ext) else {
      fileError = "Binary files cannot be displayed."
      selectedFilePath = path
      return
    }

    isLoadingFile = true
    fileError = nil
    selectedFilePath = path
    hasUnsavedChanges = false

    do {
      let content = try await FileIndexService.shared.readFile(at: path)
      fileContent = content
    } catch {
      fileError = "Could not read file: \(error.localizedDescription)"
    }
    isLoadingFile = false
  }

  private func saveCurrentFile() {
    guard let path = selectedFilePath else { return }
    isSaving = true
    let content = fileContent
    Task {
      do {
        try await FileIndexService.shared.writeFile(at: path, content: content)
        await MainActor.run {
          hasUnsavedChanges = false
          isSaving = false
        }
      } catch {
        await MainActor.run {
          isSaving = false
        }
      }
    }
  }

  private func expandToFile(_ filePath: String) {
    let relative = filePath.replacingOccurrences(of: projectPath + "/", with: "")
    let parts = relative.components(separatedBy: "/")
    var accumulated = projectPath
    for part in parts.dropLast() {
      accumulated += "/" + part
      expandedPaths.insert(accumulated)
    }
  }
}

// MARK: - FileTreeNodeView

/// Recursive view that renders a single ``FileTreeNode`` and, when expanded, its children.
private struct FileTreeNodeView: View {
  let node: FileTreeNode
  let depth: Int
  @Binding var selectedFilePath: String?
  @Binding var expandedPaths: Set<String>
  let onSelectFile: (String) -> Void

  private var isExpanded: Bool {
    expandedPaths.contains(node.path)
  }

  private var isSelected: Bool {
    !node.isDirectory && selectedFilePath == node.path
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: handleTap) {
        HStack(spacing: 4) {
          // Indentation
          if depth > 0 {
            Spacer()
              .frame(width: CGFloat(depth) * 12)
          }

          // Chevron (directories only) or spacer
          if node.isDirectory {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption2)
              .foregroundColor(.secondary)
              .frame(width: 12)
          } else {
            Spacer()
              .frame(width: 12)
          }

          // Icon
          Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
            .font(.caption)
            .foregroundColor(node.isDirectory ? .secondary : fileIconColor(for: node.name))
            .frame(width: 16)

          // Name
          Text(node.name)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(node.isDirectory ? .medium : .regular)
            .lineLimit(1)
            .foregroundColor(isSelected ? .white : .primary)

          Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 5)
            .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      // Children
      if node.isDirectory && isExpanded, let children = node.children {
        ForEach(children) { child in
          FileTreeNodeView(
            node: child,
            depth: depth + 1,
            selectedFilePath: $selectedFilePath,
            expandedPaths: $expandedPaths,
            onSelectFile: onSelectFile
          )
        }
      }
    }
  }

  private func handleTap() {
    if node.isDirectory {
      if isExpanded {
        expandedPaths.remove(node.path)
      } else {
        expandedPaths.insert(node.path)
      }
    } else {
      onSelectFile(node.path)
    }
  }

  private func fileIcon(for name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "swift":              return "swift"
    case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
    case "json":               return "curlybraces"
    case "md", "markdown":     return "doc.richtext"
    case "html", "htm":        return "globe"
    case "css", "scss", "sass": return "paintbrush"
    case "sh", "bash", "zsh":  return "terminal"
    case "yaml", "yml":        return "list.bullet.indent"
    case "xml":                return "chevron.left.forwardslash.chevron.right"
    case "py":                 return "chevron.left.forwardslash.chevron.right"
    case "rb":                 return "diamond"
    case "go":                 return "chevron.left.forwardslash.chevron.right"
    case "rs":                 return "chevron.left.forwardslash.chevron.right"
    default:                   return "doc.text"
    }
  }

  private func fileIconColor(for name: String) -> Color {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "swift":              return .orange
    case "js", "jsx":          return .yellow
    case "ts", "tsx":          return .blue
    case "json":               return .green
    case "md", "markdown":     return .secondary
    case "html", "htm":        return .orange
    case "css", "scss", "sass": return .purple
    case "sh", "bash", "zsh":  return .green
    case "yaml", "yml":        return .mint
    case "py":                 return .blue
    case "rb":                 return .red
    case "go":                 return .teal
    case "rs":                 return .orange
    default:                   return .secondary
    }
  }
}

// MARK: - CETextViewRepresentable

/// SwiftUI wrapper around ``CodeEditTextView/TextView`` (an NSView subclass).
///
/// Embeds the text view inside an ``NSScrollView`` so it behaves like a proper editor.
/// Changes to `text` from outside are reflected in the view; edits inside invoke `onTextChange`.
public struct CETextViewRepresentable: NSViewRepresentable {

  @Binding var text: String
  let onTextChange: () -> Void

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder

    let textView = TextView(
      string: text,
      font: .monospacedSystemFont(ofSize: 12, weight: .regular),
      textColor: .labelColor,
      lineHeightMultiplier: 1.3,
      wrapLines: false,
      isEditable: true,
      isSelectable: true,
      letterSpacing: 1.0,
      useSystemCursor: true,
      delegate: context.coordinator
    )
    textView.edgeInsets = HorizontalEdgeInsets(left: 8, right: 8)

    scrollView.documentView = textView
    context.coordinator.textView = textView
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = context.coordinator.textView else { return }
    // Only update the underlying storage when the binding value actually differs
    // to avoid clobbering the cursor position on every keystroke.
    if textView.string != text {
      context.coordinator.isUpdatingFromBinding = true
      textView.string = text
      context.coordinator.isUpdatingFromBinding = false
    }
  }

  // MARK: - Coordinator

  public class Coordinator: NSObject, TextViewDelegate {
    var parent: CETextViewRepresentable
    weak var textView: TextView?
    var isUpdatingFromBinding = false

    init(parent: CETextViewRepresentable) {
      self.parent = parent
    }

    public func textView(
      _ textView: TextView,
      didReplaceContentsIn range: NSRange,
      with string: String
    ) {
      guard !isUpdatingFromBinding else { return }
      let newText = textView.string
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.parent.text = newText
        self.parent.onTextChange()
      }
    }
  }
}

// MARK: - Preview

#Preview {
  FileExplorerView(
    session: CLISession(
      id: "preview-session",
      projectPath: "/Users/developer/Developing/AgentHub",
      branchName: "main",
      isWorktree: false,
      lastActivityAt: Date(),
      messageCount: 0,
      isActive: false
    ),
    projectPath: "/Users/developer/Developing/AgentHub",
    onDismiss: {}
  )
}
