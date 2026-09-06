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

  /// Both heights are re-set on every layout pass, because the height stock draws is not
  /// the same on every phone: see `StockMetrics.rowHeight(forWidth:)`.
  private lazy var keyboardViewHeight = keyboardView.heightAnchor.constraint(
    equalToConstant: Self.declaredHeight(forWidth: view.bounds.width))

  /// The height to ask for, which is stock's plate **less thirteen pixels iOS will not
  /// give a custom keyboard.**
  ///
  /// Measured on a 402pt simulator, 2026-09-05, with both keyboards in the same Contacts
  /// search field: stock's plate runs y 1617-2410 and the bottom of a custom keyboard's
  /// input view is pinned at 2397 whatever height it asks for — 765 put its top at 1632,
  /// 793 put its top at 1604, and both ended at 2397. iOS gives its own globe and
  /// dictation strip those last 13px; stock's plate simply extends over them.
  ///
  /// So a keyboard as tall as stock's plate sits 13px high, every row 13px above stock's
  /// in a side-by-side, which is what a whole afternoon of otherwise-identical
  /// measurements kept showing. Asking for 13px less puts the four key rows exactly on
  /// stock's and gives up the bottom 13px of plate instead, which is the right trade:
  /// the rows are where the fingers go, and the band underneath is dark either way.
  ///
  /// **Measured on one device.** Whether the 13 is the same on a phone of another size
  /// was not checked.
  private static let systemBottomInset: CGFloat = 13 / 3

  private static func declaredHeight(forWidth width: CGFloat) -> CGFloat {
    StockMetrics.totalHeight(forWidth: width) - systemBottomInset
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    clearThePlate()

    let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
    controller = KeyboardController(
      width: width,
      lexicon: EnglishLexicon.make(),
      document: ProxyDocument(proxy: textDocumentProxy),
    )

    keyboardView = KeyboardView(frame: view.bounds)
    keyboardView.onKey = { [weak self] key, point in
      guard let self else { return }
      // The globe is the one key the controller cannot service, and it is also the one
      // key this view never sees a touch for: `wireGlobe` below puts an invisible
      // control over it and UIKit hands that control's events straight to
      // `handleInputModeList(from:with:)`, which does both the tap and the long-press
      // keyboard list. The guard is what keeps a stray report from reaching a controller
      // that has no answer for it.
      guard key.role != .nextKeyboard else { return }
      self.controller.handle(key, at: point)
    }
    keyboardView.wireGlobe(to: self, action: #selector(handleInputModeList(from:with:)))
    keyboardView.onBubble = { [weak self] text in self?.controller.commitBubble(text) }
    view.addSubview(keyboardView)

    controller.onChange = { [weak self] in self?.render() }
    controller.hasGlobeKey = needsInputModeSwitchKey

    // An extension does not inherit the stock keyboard's metrics; it declares its own.
    // Matching them is therefore something this project does explicitly, from the
    // measurements in SPEC.md Appendix A.
    //
    // The keyboard view is pinned rather than autoresized, and given the same height, so
    // that it is exactly as tall as the keys it draws whatever the system decides to do
    // with the input view around it. With an autoresizing mask it grew to whatever the
    // input view had become, which put a plate under nothing.
    //
    // Pinned to the bottom rather than the top, which with an equal height is the same
    // layout and says the right thing: this view sits on the bottom of whatever the
    // system gives it. Where the system puts that bottom, and the 13px it keeps for
    // itself, is `systemBottomInset`.
    keyboardView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      keyboardViewHeight,
    ])

    heightConstraint = view.heightAnchor.constraint(
      equalToConstant: Self.declaredHeight(forWidth: width))
    heightConstraint.priority = .required - 1

    followSystemAppearance()
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
    followSystemAppearance()
    controller.documentDidChange()
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    controller.hasGlobeKey = needsInputModeSwitchKey
    controller.resize(width: view.bounds.width)
    let height = Self.declaredHeight(forWidth: view.bounds.width)
    keyboardViewHeight.constant = height
    heightConstraint.constant = height
    render()
  }

  /// The appearance follows the system, and `keyboardAppearance` is deliberately ignored.
  ///
  /// This is the survey's one rejected proposal, and it was rejected by measurement rather
  /// than by argument. `UITextInputTraits.keyboardAppearance` looks like the field telling
  /// the keyboard which appearance to draw, and reading it instead of the trait collection
  /// looked like an obvious correction. Then, on a simulator in dark mode on 2026-09-05,
  /// Safari's address bar reported `keyboardAppearance == .light` (raw value 2) while
  /// `traitCollection.userInterfaceStyle` was `.dark` — and **the stock keyboard in that
  /// same field draws dark**, screenshotted side by side. Obeying the field turned this
  /// keyboard white inside a black app; obeying it is what stock does not do.
  ///
  /// The reading: `.light` predates dark mode, apps set it once and never revisited it, and
  /// the system stopped treating it as authoritative. So the trait collection wins, and
  /// `overrideUserInterfaceStyle` stays `.unspecified` — which is where it started, but now
  /// for a reason that was checked rather than by never having asked.
  ///
  /// **Not established:** whether a field asking for `.dark` inside a light app is honoured
  /// by stock. That is the case where the trait would carry real information, and no field
  /// that does it has been found to test against.
  private func followSystemAppearance() {
    view.overrideUserInterfaceStyle = .unspecified
    clearThePlate()
  }

  /// Lets the system's own keyboard background show, by refusing to paint over it.
  ///
  /// `UIInputViewController`'s `view` is already a `UIInputView` drawing the keyboard
  /// material, and this keyboard had been painting `KeyboardView.plateColor` on top of it
  /// — a constant over a material. That is why A.4 and A.9 recorded two different values
  /// for stock's light plate and could not decide between them: stock's plate is a blur of
  /// whatever the host has behind the keyboard, and it moves when that moves.
  ///
  /// Measured 2026-09-06 in a Contacts search field, this keyboard against stock in the
  /// same field within a minute, identity confirmed from the globe's long-press list each
  /// time. With the paint gone the two are **the same bytes** on both backdrops and in
  /// both appearances: light `#E1E3E6` over the contact list and `#E2E4E8` over the empty
  /// "No Results" state, dark `#171717` over both. The painted constant was `#DFE0E6`,
  /// which matched neither. SPEC.md Appendix A.11.
  ///
  /// `plateColor` is kept: the container app's preview draws the keyboard on an ordinary
  /// view with no material behind it, and there it is still the right colour to paint.
  private func clearThePlate() {
    view.backgroundColor = .clear
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

  /// The field's own `UITextInputTraits`, translated into what the routing uses.
  ///
  /// Every one of these is an `@optional` protocol requirement, so Swift hands them over
  /// as optionals and "the field did not say" is a real answer. The fallbacks are UIKit's
  /// own documented defaults, and they live here rather than in `Shared/` so that there is
  /// exactly one place to read them. SPEC.md section 11.
  var traits: DocumentTraits {
    DocumentTraits(
      autocapitalization: Self.autocapitalization(proxy.autocapitalizationType),
      returnKey: Self.returnKey(proxy.returnKeyType),
      isSecure: proxy.isSecureTextEntry ?? false,
      smartQuotes: Self.smartQuotes(proxy.smartQuotesType),
    )
  }

  /// `.no` is the only refusal; `.default` leaves it to the keyboard and `.yes` asks for
  /// it, and both of those mean the same thing here. SPEC.md Appendix A.10.
  private static func smartQuotes(_ type: UITextSmartQuotesType?) -> Bool {
    switch type {
    case .no?: return false
    case .yes?, .default?, nil: return true
    @unknown default: return true
    }
  }

  private static func autocapitalization(
    _ type: UITextAutocapitalizationType?
  ) -> DocumentTraits.Autocapitalization {
    switch type {
    case .none?: return .none
    case .words?: return .words
    case .allCharacters?: return .allCharacters
    // `.sentences` is also what UIKit documents as the default, so an absent trait and an
    // explicit `.sentences` mean the same thing and share a branch honestly.
    case .sentences?, nil: return .sentences
    @unknown default: return .sentences
    }
  }

  /// What the field asked its return key to be.
  ///
  /// `.google` and `.yahoo` are search keys from before those were separate products, and
  /// stock draws all three the same, which is why they collapse into one case here rather
  /// than being carried and then thrown away at the point of drawing.
  private static func returnKey(_ type: UIReturnKeyType?) -> DocumentTraits.ReturnKey {
    switch type {
    case .go?: return .go
    case .join?: return .join
    case .next?: return .next
    case .route?: return .route
    case .search?, .google?, .yahoo?: return .search
    case .send?: return .send
    case .done?: return .done
    case .emergencyCall?: return .emergencyCall
    case .continue?: return .continue
    case .default?, nil: return .newline
    @unknown default: return .newline
    }
  }

  func insertText(_ text: String) { proxy.insertText(text) }
  func deleteBackward() { proxy.deleteBackward() }
}
