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
  private var shift: ShiftState = .off
  private var needsNextKeyboard = true

  /// Whether letters are drawn as capitals. Both shifted states say yes; the glyph on
  /// the shift cap is what tells them apart.
  private var isShifted: Bool { shift != .off }

  /// What the field asked its return key to be.
  private var returnKey: DocumentTraits.ReturnKey = .newline

  /// Whether the action return key is greyed out. See `KeyboardController.returnKeyIsDimmed`.
  private var returnKeyIsDimmed = false

  /// A field that asked for `Go`, `Search`, `Send` and the rest gets stock's blue return
  /// key; a field that said nothing gets the grey one with the ↵ glyph; and an action key
  /// that has nothing to submit yet gets greyed out.
  private var returnAppearance: ReturnKeyAppearance {
    guard returnKey.isAction else { return .plain }
    return returnKeyIsDimmed ? .dimmedAction : .action
  }

  /// How the return key is drawn. Three states rather than two booleans, because a plain
  /// `↵` key is never dimmed and a pair of flags would let it be.
  enum ReturnKeyAppearance {
    case plain
    case action
    case dimmedAction
  }

  var onKey: ((Key, CGPoint) -> Void)?
  var onBubble: ((String) -> Void)?

  var bar: CandidateBar = .empty {
    didSet { updateBar() }
  }

  private let barStack = UIStackView()
  private var bubbleLabels: [UILabel] = []
  private var dividers: [UIView] = []

  /// What turns a held delete key into more than one delete. Held here rather
  /// than in the controller because the hold is a property of the touch, and the touch
  /// is this view's; the controller sees the same single delete it always saw, just more
  /// of them. Stock waits about four tenths of a second and then repeats about ten times
  /// a second, and it accelerates into whole words after a while — this does the first
  /// two and not the third, which SPEC.md section 10 records as the difference.
  private var deleteRepeat: Timer?

  /// How long a delete has to be held before it starts repeating, and how fast it then
  /// repeats. Stock's are about these; SPEC.md section 10 carries them as tunables that
  /// were not timed off a stock keyboard. They are properties rather than constants so a
  /// test can shorten them — a test that waits out the real ones is a test that measures
  /// the machine it runs on as much as the code.
  var deleteRepeatDelay: TimeInterval = 0.4
  var deleteRepeatInterval: TimeInterval = 0.1

  /// An invisible control over the globe cap, for a host that can wire
  /// `handleInputModeList(from:with:)` to it. See `wireGlobe(to:action:)`.
  private let globeControl = UIControl()

  /// The key preview: the little bubble that appears above a key while it is held.
  /// Part of what makes the keyboard read as stock, so it is a requirement rather than
  /// a flourish. See SPEC.md section 4.
  private let preview = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUpBar()
    setUpPreview()
    // Inert until a host asks for it. A control with no targets would still swallow the
    // touch, and the container app's try-it keyboard has no input modes to list.
    globeControl.isUserInteractionEnabled = false
    addSubview(globeControl)
  }

  /// Hands the globe key to a `UIInputViewController`.
  ///
  /// The keyboard list on a long press is not something a keyboard can draw for itself:
  /// `handleInputModeList(from:with:)` is the only route, and it wants a `UIControl` and
  /// the touch event that UIKit hands a control — neither of which a plate that
  /// hit-tests its own touches can supply. So the globe cap gets an invisible control on
  /// top of it, and the host puts that selector on it. The same selector also handles
  /// the short tap, which is why the extension no longer calls
  /// `advanceToNextInputMode()` itself.
  func wireGlobe(to target: Any, action: Selector) {
    globeControl.addTarget(target, action: action, for: .allTouchEvents)
    globeControl.addTarget(self, action: #selector(globeTouchDown), for: .touchDown)
    globeControl.addTarget(
      self, action: #selector(globeTouchUp),
      for: [.touchUpInside, .touchUpOutside, .touchCancel],
    )
    globeControl.isUserInteractionEnabled = true
  }

  @objc private func globeTouchDown() {
    globeCap?.backgroundColor = Self.pressedKeyColor
  }

  @objc private func globeTouchUp() {
    globeCap?.backgroundColor = Self.capMaterial
  }

  private var globeCap: KeyCap? { cap(for: .nextKeyboard) }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: - Layout

  /// Redraws from a controller's current state. Both hosts — the keyboard extension and
  /// the container app's try-it surface — call exactly this, so neither can drift from
  /// the other in how it renders the same state.
  func apply(_ controller: KeyboardController, needsNextKeyboard: Bool) {
    if geometry?.width != controller.geometry.width
      || geometry?.plane != controller.geometry.plane
      || geometry?.hasGlobeKey != controller.geometry.hasGlobeKey
      || returnKey != controller.traits.returnKey
      || returnKeyIsDimmed != controller.returnKeyIsDimmed
    {
      returnKeyIsDimmed = controller.returnKeyIsDimmed
      configure(
        geometry: controller.geometry,
        shift: controller.shift,
        needsNextKeyboard: needsNextKeyboard,
        returnKey: controller.traits.returnKey,
      )
    } else {
      setShift(controller.shift)
    }
    bar = controller.bar
  }

  func configure(
    geometry: KeyboardGeometry,
    shift: ShiftState,
    needsNextKeyboard: Bool,
    returnKey: DocumentTraits.ReturnKey = .newline,
  ) {
    self.geometry = geometry
    self.shift = shift
    self.needsNextKeyboard = needsNextKeyboard
    self.returnKey = returnKey
    rebuildKeys()
  }

  func setShift(_ shift: ShiftState) {
    self.shift = shift
    guard let geometry else { return }
    for key in geometry.keys {
      guard let letter = key.letter, let label = (keyViews[key.id] as? KeyCap)?.label else {
        continue
      }
      label.text = isShifted ? String(letter).uppercased() : String(letter)
    }
    for key in geometry.keys {
      guard let cap = keyViews[key.id] as? KeyCap else { continue }
      cap.accessibilityLabel = accessibilityLabel(for: key)
    }
    if let shiftKey = geometry.keys.first(where: { $0.role == .shift }),
      let cap = keyViews[shiftKey.id] as? KeyCap
    {
      cap.glyph.image = symbolName(for: shiftKey).flatMap {
        UIImage(systemName: $0, withConfiguration: Self.symbolConfiguration)
      }
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
      cap.label.font = .systemFont(ofSize: key.letter != nil ? 25 : 18)
      cap.label.textColor = Self.foregroundColor(for: key, appearance: returnAppearance)
      cap.glyph.tintColor = Self.foregroundColor(for: key, appearance: returnAppearance)
      cap.glyph.image = symbolName(for: key).flatMap {
        UIImage(systemName: $0, withConfiguration: Self.symbolConfiguration)
      }
      cap.backgroundColor = Self.restingColor(for: key, appearance: returnAppearance)
      cap.isAccessibilityElement = true
      cap.accessibilityTraits = .keyboardKey
      cap.accessibilityLabel = accessibilityLabel(for: key)
      addSubview(cap)
      keyViews[key.id] = cap
    }
    bringSubviewToFront(preview)
    layOutBar()
  }

  /// What VoiceOver says a key is, which is not always what the key draws.
  ///
  /// Every stock key answers to VoiceOver, and until 2026-09-05 half of these did not: a
  /// cap whose content is a `UIImageView` — shift, delete, the globe, and the return key
  /// whenever it draws a glyph — exposed nothing at all, and neither did the blank space
  /// bar. The keys that did were exposed by accident, through the `UILabel` inside them.
  ///
  /// It has a second use that is worth writing down because it cost an evening to find.
  /// A click driven at the simulator through System Events is delivered as an
  /// accessibility activation, so it lands only on elements the app exposes and it lands
  /// at their centre. Before this, driving the keyboard from a script could press a
  /// letter or `123` and silently did nothing at all on shift, delete or space — which
  /// reads exactly like a keyboard whose bottom rows are dead.
  private func accessibilityLabel(for key: Key) -> String {
    switch key.role {
    case .letter(let c): return isShifted ? String(c).uppercased() : String(c)
    case .space: return "space"
    case .delete: return "delete"
    case .shift:
      switch shift {
      case .off: return "shift"
      case .oneShot: return "shift, on"
      case .locked: return "caps lock"
      }
    case .newline:
      let word = Self.returnKeyWord(returnKey)
      return word.isEmpty ? "return" : word
    case .plane(let plane):
      switch plane {
      case .letters: return "letters"
      case .numbers: return "numbers"
      case .symbols: return "symbols"
      }
    case .nextKeyboard: return "next keyboard"
    }
  }

  /// The word on a cap, or `""` for a cap that draws a symbol instead.
  ///
  /// The space bar is blank on stock and was labelled "space" here. The return key is a
  /// glyph for every case iOS 26 has been seen drawing one for, and a word only for the
  /// cases nobody has put in front of a stock keyboard yet.
  private func title(for key: Key) -> String {
    switch key.role {
    case .letter(let c): return isShifted ? String(c).uppercased() : String(c)
    case .space: return ""
    case .newline: return Self.returnKeyWord(returnKey)
    case .plane(let plane): return plane == .letters ? "ABC" : (plane == .numbers ? "123" : "#+=")
    case .shift, .delete, .nextKeyboard: return ""
    }
  }

  /// The SF Symbol a cap draws, or `nil` when it draws text.
  private func symbolName(for key: Key) -> String? {
    switch key.role {
    case .shift:
      switch shift {
      case .off: return "shift"
      case .oneShot: return "shift.fill"
      // Stock draws a barred arrow while caps lock is on, not a filled one. Drawing the
      // filled arrow for both is what made the latch invisible before it existed.
      case .locked: return "capslock.fill"
      }
    case .delete: return "delete.backward"
    case .nextKeyboard: return "globe"
    case .newline: return Self.returnKeySymbol(returnKey)
    default: return nil
    }
  }

  /// The glyph stock draws on the return key, or `nil` where it draws a word.
  ///
  /// Two of these were measured on a simulator on 2026-09-05, side by side with this
  /// keyboard in the same field: `arrow.right` in Safari's address bar, whose field asks
  /// for `.go`, and `magnifyingglass` in a Contacts search field, which asks for
  /// `.search`. `return` for the plain key was measured earlier the same day.
  ///
  /// **The rest are unmeasured and deliberately draw words.** Stock may well have a glyph
  /// for `.send` and `.done` too; no field asking for either has been put beside this
  /// keyboard, and guessing a symbol name is exactly the kind of thing that looks right in
  /// the source and wrong on a phone.
  private static func returnKeySymbol(_ key: DocumentTraits.ReturnKey) -> String? {
    switch key {
    case .newline: return "return"
    case .go: return "arrow.right"
    case .search: return "magnifyingglass"
    default: return nil
    }
  }

  /// The word for the cases with no measured glyph. Empty for the ones that draw one.
  private static func returnKeyWord(_ key: DocumentTraits.ReturnKey) -> String {
    switch key {
    case .newline, .go, .search: return ""
    case .send: return "Send"
    case .join: return "Join"
    case .next: return "Next"
    case .route: return "Route"
    case .done: return "Done"
    case .emergencyCall: return "Emergency Call"
    case .continue: return "Continue"
    }
  }

  /// The weight the glyph keys are drawn at.
  ///
  /// `.light` was thinner than stock and it showed. Counting lit pixels inside each
  /// glyph's bounding box on a stock capture and ours, side by side on a simulator
  /// 2026-09-05: shift 26.1% of its box against our 22.0%, delete 34.0% against 29.2%.
  /// Same shapes, less ink. The `123` cap had the same problem in text rather than in a
  /// symbol — stock's numerals fill an 82×40 box where ours filled 73×36 — which is why
  /// the command font above went from 16 to 18.
  private static let symbolConfiguration = UIImage.SymbolConfiguration(
    pointSize: 20, weight: .regular)

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let geometry, geometry.width == bounds.width else { return }
    for key in geometry.keys { keyViews[key.id]?.frame = key.frame }
    if let globe = geometry.keys.first(where: { $0.role == .nextKeyboard }) {
      globeControl.frame = globe.frame
      bringSubviewToFront(globeControl)
    } else {
      globeControl.frame = .zero
    }
    layOutBar()
  }

  /// The bar and the rules between its slots.
  ///
  /// Measured off a stock keyboard in a Contacts search field on a simulator, 2026-09-05,
  /// with the bar empty: two rules at x 399-401 and 801-803 of 1206, so a third and two
  /// thirds of the width and **three pixels wide, not a hairline**; 72px tall in a 153px
  /// strip, centred to within a couple of pixels. They are drawn whether or not the bar
  /// has anything in it — an empty stock bar still carries both rules, which is why this
  /// does not try to hide them.
  private func layOutBar() {
    let height = StockMetrics.suggestionBarHeight
    barStack.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    let ruleWidth = StockMetrics.barDividerWidth
    let ruleHeight = StockMetrics.barDividerHeight
    for (index, divider) in dividers.enumerated() {
      divider.frame = CGRect(
        x: (bounds.width / 3) * CGFloat(index + 1) - ruleWidth / 2,
        y: (height - ruleHeight) / 2,
        width: ruleWidth,
        height: ruleHeight,
      )
    }
  }

  // MARK: - The candidate bar

  private func setUpBar() {
    barStack.axis = .horizontal
    barStack.distribution = .fillEqually
    barStack.alignment = .fill
    addSubview(barStack)

    for index in 0..<3 {
      // Labels, not `UIButton(type: .system)`. A system button cross-fades its title on
      // `setTitle(_:for:)`, and the bar is retitled on every single tap, so the
      // suggestions visibly faded in and out while typing — reported from a phone on
      // 2026-09-05 as "the suggested word keep flickering or fading in and out which is
      // super distracting". A label's `text` changes with no animation at all.
      let label = UILabel()
      label.font = .systemFont(ofSize: 17)
      label.textColor = Self.barTextColor
      label.textAlignment = .center
      label.isUserInteractionEnabled = true
      label.tag = index
      label.addGestureRecognizer(
        UITapGestureRecognizer(target: self, action: #selector(bubbleTapped(_:))))
      bubbleLabels.append(label)
      barStack.addArrangedSubview(label)

      // Hairlines between the slots, as stock has them. They are what makes three words
      // in a row read as three offers rather than as a sentence; without them the bar
      // was the most obviously non-stock part of the keyboard in a side-by-side.
      if index > 0 {
        let divider = UIView()
        divider.backgroundColor = Self.barDividerColor
        dividers.append(divider)
        addSubview(divider)
      }
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
    for (label, title) in zip(bubbleLabels, titles) {
      label.text = title
    }
  }

  /// The three bubble titles as drawn. Exposed so a test can assert what the keyboard
  /// actually shows rather than what the controller computed, which are different claims.
  var bubbleTitlesForTesting: [String] {
    bubbleLabels.map { $0.text ?? "" }
  }

  /// What is drawn on the return and space caps, for the same reason: "the field asked
  /// for Search" and "the key says Search" are two claims and only the second is visible.
  var returnKeyTitleForTesting: String { capTitle(for: .newline) }
  var spaceBarTitleForTesting: String { capTitle(for: .space) }
  var returnKeyHasGlyphForTesting: Bool { cap(for: .newline)?.glyph.image != nil }

  /// The fill on the return cap, so a test can assert the blue rather than the intent.
  var returnKeyColorForTesting: UIColor? { cap(for: .newline)?.backgroundColor }

  /// The image actually loaded onto the shift cap. A `UIImage(systemName:)` that names a
  /// symbol this SDK does not have returns nil and draws an empty key, which is the way
  /// a wrong glyph name fails — silently, and only on a screen.
  var shiftGlyphForTesting: UIImage? { cap(for: .shift)?.glyph.image }

  /// Delivers a touch-down on a key without a `UITouch`, so a test can hold a key.
  func beginHoldForTesting(on role: KeyRole) {
    guard let key = geometry?.keys.first(where: { $0.role == role }) else { return }
    if key.role == .delete { startDeleteRepeat(for: key) }
  }

  func endHoldForTesting() { stopDeleteRepeat() }

  private func cap(for role: KeyRole) -> KeyCap? {
    guard let key = geometry?.keys.first(where: { $0.role == role }) else { return nil }
    return keyViews[key.id] as? KeyCap
  }

  private func capTitle(for role: KeyRole) -> String {
    cap(for: role)?.label.text ?? ""
  }

  @objc private func bubbleTapped(_ recognizer: UITapGestureRecognizer) {
    let text: String?
    switch recognizer.view?.tag ?? -1 {
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
    preview.backgroundColor = Self.capColor
    preview.layer.cornerRadius = StockMetrics.capCornerRadius
    preview.layer.masksToBounds = true
    preview.isHidden = true
    // The preview for a top-row key sits above the top of this view. Whether it is
    // allowed to draw there is the host's decision, not ours, so this asks and
    // `previewFrame(above:)` handles the answer either way.
    clipsToBounds = false
    addSubview(preview)
  }

  /// Where the preview goes for a key, kept inside this view when it has to be.
  ///
  /// A top-row key's preview wants to be at a negative `y`. On the stock keyboard it goes
  /// there, into the app above; a custom keyboard's input view may be clipped by its host
  /// instead, and on a phone on 2026-09-05 it was — the preview came out as a rectangle
  /// with its top sliced flat, sitting over the candidate bar and hiding a suggestion.
  ///
  /// So it is clamped. A clamped preview overlaps the bar, which is why `touchesBegan`
  /// hides the one slot it covers rather than leaving a suggestion half-readable behind
  /// it: a preview that hides a word by accident looks broken, and one that replaces it
  /// deliberately does not.
  private func previewFrame(above key: Key) -> CGRect {
    let frame = CGRect(
      x: key.frame.minX - 6, y: key.frame.minY - key.frame.height - 4,
      width: key.frame.width + 12, height: key.frame.height + 4)
    return frame.minY < 0 ? frame.offsetBy(dx: 0, dy: -frame.minY) : frame
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first, let geometry,
      let key = geometry.hitTest(touch.location(in: self))
    else { return }
    keyViews[key.id]?.backgroundColor = Self.pressedKeyColor
    if key.role == .delete { startDeleteRepeat(for: key) }
    if let letter = key.letter {
      preview.text = isShifted ? String(letter).uppercased() : String(letter)
      preview.frame = previewFrame(above: key)
      preview.isHidden = false
      hideBarSlot(under: preview.frame)
      bringSubviewToFront(preview)
    }
  }

  /// Hides whichever bar slots a clamped preview is sitting on, and only those.
  private func hideBarSlot(under frame: CGRect) {
    guard frame.minY < StockMetrics.suggestionBarHeight else { return }
    let slotWidth = bounds.width / 3
    for (index, label) in bubbleLabels.enumerated() {
      let slot = CGRect(
        x: slotWidth * CGFloat(index), y: 0,
        width: slotWidth, height: StockMetrics.suggestionBarHeight)
      label.isHidden = slot.intersects(frame)
    }
  }

  private func showAllBarSlots() {
    for label in bubbleLabels { label.isHidden = false }
  }

  /// Repeats the delete while the key is held. The point reported is the key's own
  /// centre: a repeat is not a strike anybody aimed, and the matcher does not read the
  /// point for a command key anyway.
  private func startDeleteRepeat(for key: Key) {
    stopDeleteRepeat()
    schedule(after: deleteRepeatDelay, repeats: false) { [weak self] in
      guard let self else { return }
      self.onKey?(key, key.center)
      self.schedule(after: self.deleteRepeatInterval, repeats: true) { [weak self] in
        self?.onKey?(key, key.center)
      }
    }
  }

  /// Schedules on the common run-loop modes rather than the default one.
  ///
  /// `Timer.scheduledTimer` puts a timer in `.default` only, so a run loop that has
  /// switched to tracking stops delivering it. A held key is exactly when that can
  /// happen, and a delete that stops repeating the moment something starts tracking is
  /// the kind of bug that only shows up on a device.
  ///
  /// A `Task` with `Task.sleep` was tried instead and never ran a single tick under the
  /// test host, while the timer does. Whatever the reason, a run loop is what actually
  /// delivers here, so this stays on one.
  private func schedule(
    after interval: TimeInterval, repeats: Bool, _ body: @escaping @MainActor () -> Void,
  ) {
    let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
      MainActor.assumeIsolated(body)
    }
    RunLoop.main.add(timer, forMode: .common)
    deleteRepeat = timer
  }

  private func stopDeleteRepeat() {
    deleteRepeat?.invalidate()
    deleteRepeat = nil
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    preview.isHidden = true
    showAllBarSlots()
    stopDeleteRepeat()
    guard let touch = touches.first, let geometry else { return }
    let point = touch.location(in: self)
    guard let key = geometry.hitTest(point) else { return }
    keyViews[key.id]?.backgroundColor = Self.restingColor(for: key, appearance: returnAppearance)
    // The point is passed on untouched. Rounding it to the key here would throw away
    // the only signal the matcher runs on.
    onKey?(key, point)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    preview.isHidden = true
    showAllBarSlots()
    stopDeleteRepeat()
    guard let geometry else { return }
    for key in geometry.keys {
      keyViews[key.id]?.backgroundColor = Self.restingColor(for: key, appearance: returnAppearance)
    }
  }

  // MARK: - The palette

  /// Every colour the keyboard draws with, as dynamic colours, so it follows the system
  /// appearance the way the stock keyboard does.
  ///
  /// **There are only three cap colours, and which key it is does not choose between
  /// them.** Every cap on the stock keyboard — letters, shift, delete, `123`, the space
  /// bar — is the same fill; the only cap that differs is the return key, and only when
  /// the field asked it to carry an action word, which stock fills with a fixed blue.
  ///
  /// This replaced a `letterKeyColor` / `commandKeyColor` pair carrying the older iOS
  /// arrangement, where command keys were a visibly darker grey on a light plate. iOS 26
  /// does not do that in either appearance, and the pair was drawing shift, delete, `123`
  /// and return in `#ABB3BD` against stock's white. The pair is gone rather than set to
  /// equal values, because two names for one colour is an invitation to re-diverge them.
  ///
  /// Sampled 2026-09-05 from the stock keyboard and this one photographed in the same
  /// `xcrun simctl io screenshot` on an iPhone 17 Pro simulator, which is what makes the
  /// comparison worth anything: a colour read out of one capture pipeline and rendered
  /// back through another is not a measurement of a difference. Same capture, both
  /// keyboards, brightest pixel in a 9×9 box on a flat part of the cap:
  ///
  ///                     stock       KeyBored 0.0.3 (as shipped)
  ///     plate  dark     #1B1B1D     #1F1F1F
  ///     cap    dark     #404041     #434343
  ///     plate  light    #DFE0E6     #D1D6DB
  ///     cap    light    #FFFFFF     #FFFFFF   (letters and space only)
  ///     command light   #FFFFFF     #ABB3BD
  ///     return  both    #007AFF     — no action fill at all
  ///
  /// The dark values here supersede a set read out of a screenshot Jonah supplied earlier
  /// the same day, which put the plate at `#1E1E1E` and the caps at `#434343`. Those are
  /// not wrong about his phone; they are a stock keyboard measured through a different
  /// pipeline from the one this keyboard is rendered through, and the three-point offset
  /// between the two sets is exactly the size of that difference. Rendering our own
  /// `#434343` and reading `#434343` back out of the simulator is what says the simulator
  /// capture is faithful, so the simulator pair is the one that can be compared.
  ///
  /// Every value here is now measured, including the pressed state, which this comment
  /// used to call unmeasurable because a static screenshot cannot show a key being held.
  /// A scripted one can: see `pressedKeyColor` below and SPEC.md Appendix A.12. Stock does
  /// lighten a cap on press in dark and darken one in light, and both are measurements.
  static let plateColor = dynamic(
    light: UIColor(red: 0.875, green: 0.878, blue: 0.902, alpha: 1),
    dark: UIColor(red: 0.106, green: 0.106, blue: 0.114, alpha: 1),
  )
  /// One cap colour, kept for the places where there is nothing underneath to wash over:
  /// the key preview, which floats above the keyboard and over the host's own content, and
  /// the contrast assertions, which need a colour rather than a material. It is what
  /// `capMaterial` below composites to over stock's Safari-host plate, so the two agree
  /// wherever they can both be applied.
  static let capColor = dynamic(
    light: .white,
    dark: UIColor(red: 0.251, green: 0.251, blue: 0.255, alpha: 1),
  )

  /// What a cap is actually painted with: a material in dark, and plain white in light.
  ///
  /// `capColor` above is one colour, and stock's cap is not one colour — it is a wash over
  /// the keyboard material, so it moves when the host's content behind the keyboard moves,
  /// exactly as the plate does (SPEC.md Appendix A.11). Measured on 2026-09-06 in dark
  /// appearance, this keyboard and stock in the same field minutes apart, identity checked
  /// from the globe's list each time:
  ///
  ///     host                       plate      stock cap
  ///     Safari, the start page     #1B1B1D    #404041
  ///     Contacts, the list         #171717    #3D3D3D
  ///     Settings, the list         #171717    #3D3D3D
  ///
  /// One wash over the plate fits all six channels of those two distinct states, and it is
  /// over-determined rather than fitted: solving `cap = a·C + (1-a)·plate` on the red and
  /// green channels alone gives `a = 0.25` and `C = 175`, and that pair then predicts both
  /// blue values exactly (`0.25·175 + 0.75·29 = 65`, `0.25·175 + 0.75·23 = 61`). So the
  /// dark cap is a quarter of `#AFAFAF` laid over whatever is underneath.
  ///
  /// **Light stays opaque white**, which is not a shortcut: stock's light cap reads
  /// `#FFFFFF` over both light plates measured, white is the ceiling, and there is no
  /// signal in a saturated channel to fit a wash to. Ours is byte-equal to stock there
  /// already (A.6) and a wash could only move it off.
  ///
  /// The container app draws this over its own painted `plateColor`, which is stock's
  /// Safari-host plate, so it composites to `#404041` there — the same pixels it drew
  /// before this existed.
  static let capMaterial = dynamic(
    light: .white,
    dark: UIColor(white: 175 / 255, alpha: 0.25),
  )

  /// The return key when the field asked for a word — `Go`, `Search`, `Send`. Fixed
  /// rather than dynamic: stock draws `#007AFF` in both appearances, measured in both.
  /// It is `systemBlue`'s light value, and stock does not switch to the dark one.
  static let actionKeyColor = UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)

  /// The same key with nothing yet to submit, which stock greys out rather than hiding.
  ///
  /// Measured 2026-09-06 on the stock keyboard in a freshly presented Contacts search
  /// field, before any key was struck (SPEC.md Appendix A.13):
  ///
  ///                    fill        glyph      over a plate of
  ///     dark           #747474     #818181    #171717
  ///     light          #C0C2C5     #ADAEB1    #E1E3E6
  ///
  /// The glyph is nineteen units lighter than its cap in dark and nineteen darker in
  /// light — about 1.1:1 either way, which is not a legibility failure to be fixed but the
  /// whole point of a disabled control. `everyCapIsLegibleInBothAppearances` exempts this
  /// pair and says why.
  ///
  /// Opaque, like `pressedKeyColor` and for the same reason: one backdrop per appearance
  /// was measured, which cannot determine a wash. The plate each was read over is recorded
  /// above so the fit can be finished later without re-measuring.
  static let dimmedActionKeyColor = dynamic(
    light: UIColor(red: 192 / 255, green: 194 / 255, blue: 197 / 255, alpha: 1),
    dark: UIColor(white: 116 / 255, alpha: 1),
  )

  static let dimmedActionKeyTextColor = dynamic(
    light: UIColor(red: 173 / 255, green: 174 / 255, blue: 177 / 255, alpha: 1),
    dark: UIColor(white: 129 / 255, alpha: 1),
  )

  /// A cap while a finger is on it. **Both values are now measured**, and both were wrong.
  ///
  /// The comment here used to say a static screenshot cannot show a key being held, so the
  /// dark value was chosen and the light one sampled from an unheld capture. A screenshot
  /// can show it: post the mouse-down, wait, screenshot, then post the mouse-up — the hold
  /// is the interval you control (SPEC.md Appendix A.9). Measured 2026-09-06 on the stock
  /// keyboard, delete held with text in the field so the press actually took, sampled at
  /// four corners of the cap and flat across all of them:
  ///
  ///                    stock       what this drew
  ///     dark           #7D7D7D     #6B6B6B    (18 units too dark)
  ///     light          #C5C5C9     #D9DEE3    (20 units too light, and blue where
  ///                                            stock is very nearly neutral)
  ///
  /// Held opaque rather than washed like `capMaterial`. One backdrop was measured per
  /// appearance, which cannot determine a wash — but it can rule one out: with the
  /// resting wash's own `a = 0.25`, matching `#7D7D7D` over a `#171717` plate would need
  /// `C = 431`, and there is no such colour. So the pressed cap is **not** the resting
  /// wash, and what it is instead is not established.
  ///
  /// The dark value was read over a `#171717` plate and the light one over `#E2E4E8`.
  /// If it turns out to be a wash after all, those are the plates these constants are
  /// exact over.
  static let pressedKeyColor = dynamic(
    light: UIColor(red: 197 / 255, green: 197 / 255, blue: 201 / 255, alpha: 1),
    dark: UIColor(white: 125 / 255, alpha: 1),
  )

  /// The glyph on a cap, and the text in the candidate bar. Explicit rather than
  /// inherited: an inherited text colour is what made the letters disappear.
  static let keyTextColor = dynamic(light: .black, dark: .white)

  /// The bar is dimmer than the caps, and that is a measurement rather than a taste.
  /// Sampled from a stock keyboard beside this one on Jonah's phone, 2026-09-05: the
  /// bar's text peaks at `#ABABAB` where a cap glyph peaks at white. Ours was drawing the
  /// bar at full glyph weight, which is what made three candidates read as a sentence.
  ///
  /// The light value is chosen, not sampled — there is no light-mode stock reference — and
  /// it is a dark grey rather than the equivalent dimming, because dimming it to the same
  /// degree fails the 4.5:1 contrast the tests require against the light plate.
  static let barTextColor = dynamic(
    light: UIColor(white: 0.25, alpha: 1),
    dark: UIColor(white: 0.671, alpha: 1),
  )

  /// The rule between two bar slots. `#323234`, read out of an empty Contacts search field
  /// on a stock keyboard in dark appearance, where the two rules stand at x 399-401 and
  /// 801-803 in a 1206px capture. Light reads `#B8B8B8`, at x 400-402 in the same field,
  /// running y 1659-1730 - 72 rows, the same height as dark. SPEC.md A.4 has both.
  static let barDividerColor = dynamic(
    light: UIColor(white: 184 / 255, alpha: 1),
    dark: UIColor(red: 50 / 255, green: 50 / 255, blue: 52 / 255, alpha: 1),
  )

  private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
  }

  /// The background a cap of this key should have when it is not pressed. The return key
  /// is the only cap whose colour depends on anything.
  static func restingColor(for key: Key, appearance: ReturnKeyAppearance = .plain) -> UIColor {
    guard key.role == .newline else { return capMaterial }
    switch appearance {
    case .plain: return capMaterial
    case .action: return actionKeyColor
    case .dimmedAction: return dimmedActionKeyColor
    }
  }

  /// What a cap draws its glyph in. White on the action return key in both appearances,
  /// because that cap is blue in both; and barely distinguishable from its own cap when
  /// that key is dimmed, because that is what stock draws.
  static func foregroundColor(
    for key: Key, appearance: ReturnKeyAppearance = .plain
  ) -> UIColor {
    guard key.role == .newline else { return keyTextColor }
    switch appearance {
    case .plain: return keyTextColor
    case .action: return .white
    case .dimmedAction: return dimmedActionKeyTextColor
    }
  }
}

/// One key cap. A view rather than a button so that the touch handling stays in one
/// place and every touch reports its position, which a `UIControl` action would not.
final class KeyCap: UIView {
  let label = UILabel()

  /// Command keys that stock draws as a glyph rather than a word — shift, delete, return
  /// and the globe — draw an SF Symbol here instead of text in `label`. A symbol rather
  /// than the nearest Unicode character because the weight is the point: stock's shift is
  /// a heavier outlined arrow than `⇧` renders at any size, which is visible in a
  /// side-by-side and was the fifth thing Jonah picked out of one.
  let glyph = UIImageView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = StockMetrics.capCornerRadius
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.3
    layer.shadowOffset = CGSize(width: 0, height: 1)
    layer.shadowRadius = 0
    isUserInteractionEnabled = false
    label.textAlignment = .center
    label.frame = bounds
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(label)
    glyph.contentMode = .center
    glyph.frame = bounds
    glyph.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(glyph)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
