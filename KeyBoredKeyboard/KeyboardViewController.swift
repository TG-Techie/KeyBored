// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md section 4 for the geometry, PRIVACY.md for what this does with keystrokes.

import UIKit

/// The keyboard extension's principal class, named by `NSExtensionPrincipalClass` in
/// this target's `Info.plist`.
///
/// It is deliberately thin. Everything about what typing *means* — what a space commits,
/// what delete undoes, when a word ends — lives in `KeyboardController` in `Shared/`,
/// where it can be tested and read without installing a keyboard. This file is the
/// plumbing between UIKit and that: a view, a text destination, and a size.
final class KeyboardViewController: UIInputViewController {
  private var keyboardView: KeyboardView!
  private var controller: KeyboardController!

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = KeyboardView.plateColor

    let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
    controller = KeyboardController(
      width: width,
      lexicon: EnglishLexicon.make(),
      document: ProxyDocument(proxy: textDocumentProxy),
    )

    keyboardView = KeyboardView(frame: view.bounds)
    keyboardView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    keyboardView.onKey = { [weak self] key, point in
      guard let self else { return }
      // The globe is the one key the controller cannot service: only a
      // UIInputViewController can switch keyboards.
      if key.role == .nextKeyboard {
        self.advanceToNextInputMode()
      } else {
        self.controller.handle(key, at: point)
      }
    }
    keyboardView.onBubble = { [weak self] text in self?.controller.commitBubble(text) }
    view.addSubview(keyboardView)

    controller.onChange = { [weak self] in self?.render() }

    // An extension does not inherit the stock keyboard's metrics; it declares its own.
    // Matching them is therefore something this project does explicitly, from the
    // measurements in SPEC.md Appendix A.
    let height = view.heightAnchor.constraint(equalToConstant: StockMetrics.totalHeight)
    height.priority = .required - 1
    height.isActive = true

    render()
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    controller.resize(width: view.bounds.width)
    render()
  }

  private func render() {
    keyboardView.apply(controller, needsNextKeyboard: needsInputModeSwitchKey)
  }
}

/// Adapts the host app's text field to `TextDocument`.
///
/// `UITextDocumentProxy` already has both methods; this exists so that `Shared/` never
/// has to import the extension-only half of UIKit, and so the container app can supply a
/// different destination for the same routing code.
private final class ProxyDocument: TextDocument {
  private let proxy: UITextDocumentProxy

  init(proxy: UITextDocumentProxy) {
    self.proxy = proxy
  }

  func insertText(_ text: String) { proxy.insertText(text) }
  func deleteBackward() { proxy.deleteBackward() }
}
