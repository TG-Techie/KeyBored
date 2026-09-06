// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.

import SwiftUI
import UIKit

/// The container app, which is a place to try the keyboard before installing it.
///
/// It runs the real `KeyboardController` against a real `KeyboardView` — the same two
/// types the extension uses, not a mock-up of them — so what you type here behaves
/// exactly as it will once the keyboard is enabled. That is also why it is worth having:
/// a custom keyboard is otherwise unreachable until a user has been through four screens
/// of Settings, which is a poor place to discover it does not work.
struct ContentView: View {
  var body: some View {
    TryItView()
      .ignoresSafeArea(.container, edges: .bottom)
  }
}

private struct TryItView: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> TryItViewController { TryItViewController() }
  func updateUIViewController(_ controller: TryItViewController, context: Context) {}
}

/// A text view with KeyBored underneath it, wired together the way the extension wires
/// itself to its host app.
final class TryItViewController: UIViewController {
  private let textView = UITextView()
  private var keyboardView: KeyboardView!
  private var controller: KeyboardController!

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    textView.font = .systemFont(ofSize: 20)
    textView.backgroundColor = .clear
    textView.isEditable = false  // KeyBored is the only way to put text in it.
    textView.text = ""
    textView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(textView)

    keyboardView = KeyboardView(frame: .zero)
    keyboardView.backgroundColor = KeyboardView.plateColor
    keyboardView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(keyboardView)

    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      textView.bottomAnchor.constraint(equalTo: keyboardView.topAnchor),

      keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      keyboardView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      keyboardView.heightAnchor.constraint(equalToConstant: StockMetrics.totalHeight),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let width = keyboardView.bounds.width
    guard width > 0 else { return }
    if controller == nil {
      controller = KeyboardController(
        width: width, lexicon: EnglishLexicon.make(), document: TextViewDocument(textView))
      keyboardView.onKey = { [weak self] key, point in
        // The globe does nothing here: there is no other keyboard to advance to inside
        // the container app, and pretending otherwise would be worse than an inert key.
        guard key.role != .nextKeyboard else { return }
        self?.controller.handle(key, at: point)
      }
      keyboardView.onBubble = { [weak self] text in self?.controller.commitBubble(text) }
      controller.onChange = { [weak self] in self?.render() }
    } else {
      controller.resize(width: width)
    }
    render()
  }

  private func render() {
    keyboardView.apply(controller, needsNextKeyboard: false)
  }
}

/// The container app's text destination. The extension has its own, over
/// `UITextDocumentProxy`; both are a handful of lines because `TextDocument` asks for
/// almost nothing.
private final class TextViewDocument: TextDocument {
  private let textView: UITextView

  init(_ textView: UITextView) {
    self.textView = textView
  }

  var textBeforeInput: String? { textView.text }

  func insertText(_ text: String) {
    textView.text.append(text)
  }

  func deleteBackward() {
    guard !textView.text.isEmpty else { return }
    textView.text.removeLast()
  }
}
