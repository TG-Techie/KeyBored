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

  /// Held so it can be activated once the view is in a window. See `viewDidAppear`.
  private var heightConstraint: NSLayoutConstraint!

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
    //
    // The keyboard view is pinned rather than autoresized, and given the same height, so
    // that it is exactly as tall as the keys it draws whatever the system decides to do
    // with the input view around it. With an autoresizing mask it grew to whatever the
    // input view had become, which put a plate under nothing.
    keyboardView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
      keyboardView.heightAnchor.constraint(equalToConstant: StockMetrics.totalHeight),
    ])

    heightConstraint = view.heightAnchor.constraint(
      equalToConstant: StockMetrics.totalHeight)
    heightConstraint.priority = .required - 1

    render()
  }

  /// Activating the height constraint is deferred until the view is in a window.
  ///
  /// Activated in `viewDidLoad` it does not survive: `self.view` still has
  /// `translatesAutoresizingMaskIntoConstraints` set, the autoresizing constraints that
  /// generates are at required priority, and a constraint one step below required loses
  /// to them. The keyboard then renders at whatever height the host leaves free — 690
  /// points against the 295 it asks for, measured in the simulator on 2026-09-05 — with
  /// the keys drawn at the top of a plate that reaches most of the way up the screen.
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    heightConstraint.isActive = true
  }

  /// The system's only notice that the field being typed into is not what it was.
  ///
  /// It fires for the host's edits and for this keyboard's own; `documentDidChange` is
  /// what tells them apart. Without this override the keyboard cannot see the host clear
  /// a field, and goes on capitalizing — or not — according to what it last typed rather
  /// than what is on screen.
  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    controller.documentDidChange()
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
/// `UITextDocumentProxy` already has all three members; this exists so that `Shared/`
/// never has to import the extension-only half of UIKit, and so the container app can
/// supply a different destination for the same routing code.
private final class ProxyDocument: TextDocument {
  private let proxy: UITextDocumentProxy

  init(proxy: UITextDocumentProxy) {
    self.proxy = proxy
  }

  var textBeforeInput: String? { proxy.documentContextBeforeInput }

  func insertText(_ text: String) { proxy.insertText(text) }
  func deleteBackward() { proxy.deleteBackward() }
}
