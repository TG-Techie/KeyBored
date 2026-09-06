// Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com>
// Licensed under the MIT License. See LICENSE at the repository root.
// This file is permitted to be edited by AI models and agents.
//
// References:
//   SPEC.md Appendix A for where every proportion here came from.

import UIKit

/// Draws the keys and the candidate bar, and reports where a touch landed.
///
/// It reports the raw point rather than the key, because the point is what the matcher
/// needs; the key comes along only so the controller can tell a letter from a command
/// without hit-testing twice.
final class KeyboardView: UIView {
  private(set) var geometry: KeyboardGeometry?
  private var keyViews: [KeyID: UIView] = [:]
  private var isShifted = false
  private var needsNextKeyboard = true

  var onKey: ((Key, CGPoint) -> Void)?
  var onBubble: ((String) -> Void)?

  var bar: CandidateBar = .empty {
    didSet { updateBar() }
  }

  private let barStack = UIStackView()
  private var bubbleButtons: [UIButton] = []

  /// The key preview: the little bubble that appears above a key while it is held.
  /// Part of what makes the keyboard read as stock, so it is a requirement rather than
  /// a flourish. See SPEC.md section 4.
  private let preview = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUpBar()
    setUpPreview()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: - Layout

  /// Redraws from a controller's current state. Both hosts — the keyboard extension and
  /// the container app's try-it surface — call exactly this, so neither can drift from
  /// the other in how it renders the same state.
  func apply(_ controller: KeyboardController, needsNextKeyboard: Bool) {
    if geometry?.width != controller.geometry.width
      || geometry?.plane != controller.geometry.plane
    {
      configure(
        geometry: controller.geometry,
        isShifted: controller.isShifted,
        needsNextKeyboard: needsNextKeyboard,
      )
    } else {
      setShifted(controller.isShifted)
    }
    bar = controller.bar
  }

  func configure(geometry: KeyboardGeometry, isShifted: Bool, needsNextKeyboard: Bool) {
    self.geometry = geometry
    self.isShifted = isShifted
    self.needsNextKeyboard = needsNextKeyboard
    rebuildKeys()
  }

  func setShifted(_ shifted: Bool) {
    isShifted = shifted
    guard let geometry else { return }
    for key in geometry.keys {
      guard let letter = key.letter, let label = (keyViews[key.id] as? KeyCap)?.label else {
        continue
      }
      label.text = shifted ? String(letter).uppercased() : String(letter)
    }
    if let shift = geometry.keys.first(where: { $0.role == .shift }) {
      (keyViews[shift.id] as? KeyCap)?.label.text = shifted ? "⇧" : "⇧"
      keyViews[shift.id]?.backgroundColor = shifted ? Self.letterKeyColor : Self.commandKeyColor
    }
  }

  private func rebuildKeys() {
    keyViews.values.forEach { $0.removeFromSuperview() }
    keyViews.removeAll()
    guard let geometry else { return }

    for key in geometry.keys {
      if key.role == .nextKeyboard && !needsNextKeyboard { continue }
      let cap = KeyCap(frame: key.frame)
      cap.label.text = title(for: key)
      cap.label.font = .systemFont(
        ofSize: key.letter != nil ? 25 : 16, weight: key.letter != nil ? .regular : .regular)
      cap.label.textColor = Self.keyTextColor
      cap.backgroundColor = Self.restingColor(for: key)
      addSubview(cap)
      keyViews[key.id] = cap
    }
    bringSubviewToFront(preview)
    barStack.frame = CGRect(
      x: 0, y: 0, width: bounds.width, height: StockMetrics.suggestionBarHeight)
  }

  private func title(for key: Key) -> String {
    switch key.role {
    case .letter(let c): return isShifted ? String(c).uppercased() : String(c)
    case .shift: return "⇧"
    case .delete: return "⌫"
    case .space: return "space"
    case .newline: return "return"
    case .plane(let plane): return plane == .letters ? "ABC" : (plane == .numbers ? "123" : "#+=")
    case .nextKeyboard: return "🌐"
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let geometry, geometry.width == bounds.width else { return }
    for key in geometry.keys { keyViews[key.id]?.frame = key.frame }
    barStack.frame = CGRect(
      x: 0, y: 0, width: bounds.width, height: StockMetrics.suggestionBarHeight)
  }

  // MARK: - The candidate bar

  private func setUpBar() {
    barStack.axis = .horizontal
    barStack.distribution = .fillEqually
    barStack.alignment = .fill
    addSubview(barStack)

    for index in 0..<3 {
      let button = UIButton(type: .system)
      button.titleLabel?.font = .systemFont(ofSize: 17)
      button.setTitleColor(Self.barTextColor, for: .normal)
      button.tag = index
      button.addTarget(self, action: #selector(bubbleTapped(_:)), for: .touchUpInside)
      bubbleButtons.append(button)
      barStack.addArrangedSubview(button)
    }
  }

  private func updateBar() {
    // The left slot carries the literal in quotes, the way stock marks "this is
    // exactly what you typed" as distinct from "this is a word".
    let titles = [
      bar.literal.isEmpty ? "" : "\u{201C}\(bar.literal)\u{201D}",
      bar.primary ?? "",
      bar.secondary ?? "",
    ]
    for (button, title) in zip(bubbleButtons, titles) {
      button.setTitle(title, for: .normal)
      button.isEnabled = !title.isEmpty
    }
  }

  /// The three bubble titles as drawn. Exposed so a test can assert what the keyboard
  /// actually shows rather than what the controller computed, which are different claims.
  var bubbleTitlesForTesting: [String] {
    bubbleButtons.map { $0.title(for: .normal) ?? "" }
  }

  @objc private func bubbleTapped(_ sender: UIButton) {
    let text: String?
    switch sender.tag {
    case 0: text = bar.literal
    case 1: text = bar.primary
    default: text = bar.secondary
    }
    guard let text, !text.isEmpty else { return }
    onBubble?(text)
  }

  // MARK: - Touches

  private func setUpPreview() {
    preview.textAlignment = .center
    preview.font = .systemFont(ofSize: 38)
    preview.textColor = Self.keyTextColor
    preview.backgroundColor = Self.letterKeyColor
    preview.layer.cornerRadius = 8
    preview.layer.masksToBounds = true
    preview.isHidden = true
    addSubview(preview)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first, let geometry,
      let key = geometry.hitTest(touch.location(in: self))
    else { return }
    keyViews[key.id]?.backgroundColor = Self.pressedKeyColor
    if let letter = key.letter {
      preview.text = isShifted ? String(letter).uppercased() : String(letter)
      preview.frame = CGRect(
        x: key.frame.minX - 6, y: key.frame.minY - key.frame.height - 4,
        width: key.frame.width + 12, height: key.frame.height + 4)
      preview.isHidden = false
      bringSubviewToFront(preview)
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    preview.isHidden = true
    guard let touch = touches.first, let geometry else { return }
    let point = touch.location(in: self)
    guard let key = geometry.hitTest(point) else { return }
    keyViews[key.id]?.backgroundColor = Self.restingColor(for: key)
    // The point is passed on untouched. Rounding it to the key here would throw away
    // the only signal the matcher runs on.
    onKey?(key, point)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    preview.isHidden = true
    guard let geometry else { return }
    for key in geometry.keys {
      keyViews[key.id]?.backgroundColor = Self.restingColor(for: key)
    }
  }

  // MARK: - The palette

  /// Every colour the keyboard draws with, as dynamic colours, so it follows the system
  /// appearance the way the stock keyboard does.
  ///
  /// Both sets are sampled from screenshots of the stock keyboard rather than guessed,
  /// like the geometry; see SPEC.md Appendix A. The dark ones were read out of a
  /// simulator screenshot Jonah supplied on 2026-09-05, averaging a 7×7 box at each
  /// point: plate `#1E1E1E`, every cap `#434343`, glyphs white.
  ///
  /// **In dark mode a command cap is the same grey as a letter cap.** That is not a
  /// simplification, it is what the stock keyboard does, and it is the opposite of the
  /// light arrangement where command keys are visibly darker than letter keys. The only
  /// value here that is chosen rather than measured is the dark pressed state: a static
  /// screenshot cannot show a key being held, and stock lightens a cap on press in dark
  /// mode where it darkens one in light mode.
  ///
  /// The reason this is a palette at all rather than five literals: it used to be four
  /// hardcoded light-mode colours and one dynamic text colour, `UILabel`'s default
  /// `.label`. In dark mode that resolved to white and every letter cap was also white,
  /// so on a real phone the letters were invisible while `123`, `return` and `⌫` — the
  /// only caps drawn on the grey command colour — stayed legible. A palette that is
  /// half fixed and half dynamic cannot be right in both appearances.
  static let plateColor = dynamic(
    light: UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1),
    dark: UIColor(white: 0.122, alpha: 1),
  )
  static let letterKeyColor = dynamic(
    light: .white,
    dark: UIColor(white: 0.263, alpha: 1),
  )
  static let commandKeyColor = dynamic(
    light: UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1),
    dark: UIColor(white: 0.263, alpha: 1),
  )
  /// The light value is sampled; the dark one is chosen, for the reason above.
  static let pressedKeyColor = dynamic(
    light: UIColor(red: 0.85, green: 0.87, blue: 0.89, alpha: 1),
    dark: UIColor(white: 0.42, alpha: 1),
  )

  /// The glyph on a cap, and the text in the candidate bar. Explicit rather than
  /// inherited: an inherited text colour is what made the letters disappear.
  static let keyTextColor = dynamic(light: .black, dark: .white)
  static let barTextColor = dynamic(light: .black, dark: .white)

  private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
  }

  /// The background a cap of this key should have when it is not pressed.
  static func restingColor(for key: Key) -> UIColor {
    key.letter == nil && key.role != .space ? commandKeyColor : letterKeyColor
  }
}

/// One key cap. A view rather than a button so that the touch handling stays in one
/// place and every touch reports its position, which a `UIControl` action would not.
private final class KeyCap: UIView {
  let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 5
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.3
    layer.shadowOffset = CGSize(width: 0, height: 1)
    layer.shadowRadius = 0
    isUserInteractionEnabled = false
    label.textAlignment = .center
    label.frame = bounds
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(label)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
