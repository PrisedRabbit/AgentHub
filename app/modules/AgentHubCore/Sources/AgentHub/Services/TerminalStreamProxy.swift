//
//  TerminalStreamProxy.swift
//  AgentHub
//
//  Central registry bridging PTY terminal sessions to WebSocket clients.
//

import Combine
import Foundation

/// Central registry bridging PTY terminal sessions to WebSocket clients.
/// @MainActor because it interacts with ManagedLocalProcessTerminalView (a view class).
@MainActor
public final class TerminalStreamProxy {
  public static let shared = TerminalStreamProxy()
  private init() {}

  // sessionId → weak reference to the terminal view
  private var terminals: [String: WeakTerminalRef] = [:]
  // sessionId → active Combine subscriptions (one per registered terminal)
  private var cancellables: [String: AnyCancellable] = [:]
  // sessionId → list of WebSocket listeners
  private var listeners: [String: [any TerminalListener]] = [:]

  // MARK: - Registration (called by EmbeddedTerminalView on appear/disappear)

  public func register(sessionId: String, terminal: ManagedLocalProcessTerminalView) {
    terminals[sessionId] = WeakTerminalRef(terminal)
    // Subscribe to PTY output and broadcast to all listeners for this session
    cancellables[sessionId] = terminal.dataPublisher
      .receive(on: DispatchQueue.global(qos: .userInteractive))
      .sink { [weak self] data in
        Task { @MainActor [weak self] in
          self?.broadcast(sessionId: sessionId, data: data)
        }
      }
  }

  public func unregister(sessionId: String) {
    cancellables.removeValue(forKey: sessionId)
    terminals.removeValue(forKey: sessionId)
    // Notify listeners the session ended
    listeners[sessionId]?.forEach { $0.onClose() }
    listeners.removeValue(forKey: sessionId)
  }

  // MARK: - Listener management (called by AgentHubWebServer)

  public func addListener(_ listener: any TerminalListener, for sessionId: String) {
    listeners[sessionId, default: []].append(listener)
  }

  public func removeListener(_ listener: any TerminalListener, for sessionId: String) {
    listeners[sessionId]?.removeAll { $0 === listener }
  }

  // MARK: - Data flow

  private func broadcast(sessionId: String, data: Data) {
    listeners[sessionId]?.forEach { $0.onData(data) }
  }

  public func writeInput(sessionId: String, data: Data) {
    terminals[sessionId]?.value?.writeToProcess(data)
  }

  public func resize(sessionId: String, cols: Int, rows: Int) {
    // Terminal resize from web client — placeholder for MVP.
    // Full implementation: call setTerminalSize on the terminal view.
  }

  // MARK: - Inspection

  public func hasTerminal(for sessionId: String) -> Bool {
    terminals[sessionId]?.value != nil
  }
}

// MARK: - Supporting types

private final class WeakTerminalRef {
  weak var value: ManagedLocalProcessTerminalView?
  init(_ value: ManagedLocalProcessTerminalView) { self.value = value }
}

/// Callbacks from TerminalStreamProxy to a WebSocket connection handler.
/// `AnyObject` constraint required for `removeAll { $0 === listener }` identity comparison.
public protocol TerminalListener: AnyObject {
  func onData(_ data: Data)
  func onClose()
}
