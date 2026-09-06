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

  /// The key previews currently on screen, one per finger.
  ///
  /// **One shared label was correct only because of a bug.** Until 0.0.6 this view had
  /// `isMultipleTouchEnabled` false, so UIKit delivered one finger and discarded the rest
  /// and there was never a second preview to draw. Turning multi-touch on removed that
  /// accidental guarantee and left the single label behind: the second finger down
  /// retargeted the first finger's preview instead of adding one, and the first finger
  /// lifting hid it while the second was still down. Reported on 0.0.7 as the preview
  /// "still not reliably showing when a tap matches a key".
  ///
  /// A preview belongs to a finger, so it is keyed by one. Part of what makes the
  /// keyboard read as stock, so it is a requirement rather than a flourish.
  /// See SPEC.md section 4.
  private var previews: [ObjectIdentifier: KeyPreview] = [:]

  /// Previews that have been used and are waiting to be used again, so that typing does
  /// not allocate a view per keystroke.
  private var sparePreviews: [KeyPreview] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUpBar()
    setUpPreview()
    // Without this UIKit hands this view the first finger of a multi-touch sequence and
    // discards every other one, which at typing speed is most of them. See `touchesBegan`.
    isMultipleTouchEnabled = true
    // The plate has to be drawn for the plate to be touchable. See `touchableFill`.
    backgroundColor = Self.touchableFill
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
    // Punctuation is not shifted: the period key stock draws in an address field is a
    // period whatever the shift is doing.
    case .punctuation(let c): return String(c)
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
    case .punctuation(let c): return String(c)
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
      // No gesture recognizer and no interaction: a bar slot is resolved from the touch's
      // coordinate by `target(at:)`, the same way a key is. A label that took its own
      // touches would be a second opinion about what a point means, and the whole reason
      // this view hit-tests itself is that there can only be one. See `hitTest`.
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

  /// The word offered in a bar slot, or nothing when that slot is empty.
  private func bubbleText(_ slot: Int) -> String? {
    let text: String?
    switch slot {
    case 0: text = bar.literal
    case 1: text = bar.primary
    default: text = bar.secondary
    }
    guard let text, !text.isEmpty else { return nil }
    return text
  }

  // MARK: - Touches

  private func setUpPreview() {
    // Asked for and not granted. A keyboard extension's drawing is cut at its input
    // view's edge by the process that composites it, not by any view in the chain — every
    // ancestor up to `_UIHostedWindow` reports `clipsToBounds` false and the preview is
    // sliced flat anyway. This stays because it is the truthful statement of intent and
    // costs nothing; `previewFrame(above:)` deals with the answer.
    clipsToBounds = false
  }

  /// A preview for this finger, reused if one is going spare.
  private func preview(for touch: UITouch) -> KeyPreview {
    let id = ObjectIdentifier(touch)
    if let existing = previews[id] { return existing }
    let view = sparePreviews.popLast() ?? KeyPreview()
    previews[id] = view
    addSubview(view)
    bringSubviewToFront(view)
    return view
  }

  /// Takes this finger's preview off the screen and keeps it for the next one.
  private func dismissPreview(for touch: UITouch) {
    guard let view = previews.removeValue(forKey: ObjectIdentifier(touch)) else { return }
    view.removeFromSuperview()
    sparePreviews.append(view)
  }

  /// Where the preview goes for a key: stock's teardrop, pushed into view when it has to be.
  ///
  /// The rectangle runs from the top of the bulb down to the bottom of the cap, because
  /// the stem joins the two and the whole shape is drawn inside it. Its width is the
  /// bulb's, which overhangs the cap on both sides. `KeyPreview` draws the bulb, the stem
  /// and the letter from these bounds and the cap height it is given.
  ///
  /// **Rows 1 to 3 get stock's geometry exactly; row 0 cannot have it.** Stock's bulb
  /// rises 207px above a 135px cap, and above row 0 this keyboard owns only the 104px of
  /// its suggestion bar — a keyboard extension's drawing is cut at its input view's edge
  /// by the compositor, so the rest is simply not drawn. It was cut on a phone on
  /// 2026-09-05, and on 2026-09-06 the cause was established rather than inferred: every
  /// ancestor up to `_UIHostedWindow` reports `clipsToBounds` false and the preview is
  /// sliced flat all the same.
  ///
  /// Asking for a taller input view so the room is ours was tried and reverted the same
  /// day. The rows do stay where they were, but iOS extends the visible plate with the
  /// input view, so the keyboard stood 34pt taller than stock with an empty band above
  /// the bar — the shape of the defect he had reported that morning. SPEC.md A.19.
  ///
  /// So row 0's preview rises as far as there is room and no further. **The whole frame
  /// used to be pushed down instead**, which kept the shape's proportions and moved its
  /// foot off the key it belongs to: on the top row it hung a third of a cap below its own
  /// letter, into the row beneath. A preview is anchored to its key at the bottom and free
  /// at the top, so the top is what gives.
  ///
  /// It still ends up over the suggestion bar. It is opaque and in front, so it covers the
  /// part of a word it sits on and leaves the rest legible. **It used to hide the whole
  /// slot underneath it, and that was the flicker** — a suggestion blinking out and back
  /// once per top-row keystroke, reported 2026-09-05 and visible in `IMG_8416` as a blank
  /// middle cell in the one frame captured mid-press. Covering part of a word for the
  /// length of a press is the smaller wrong.
  private func previewFrame(above key: Key) -> CGRect {
    let cap = key.frame
    let width = cap.width * StockMetrics.previewBulbWidthInCaps
    let top = max(0, cap.minY - cap.height * StockMetrics.previewRiseInCaps)
    return CGRect(x: cap.midX - width / 2, y: top, width: width, height: cap.maxY - top)
  }

  /// What a point on this keyboard means. Every touch resolves to exactly one of these,
  /// once, and everything the touch does follows from it.
  private enum Target {
    case key(Key)
    case bubble(Int)
  }

  /// Which target each finger currently down is holding, so that several can be down at
  /// once and each is released as the thing it pressed.
  private var held: [ObjectIdentifier: Target] = [:]

  /// The finger the delete repeat belongs to, so that lifting a different finger does not
  /// stop it and lifting this one does.
  private var deleteRepeatTouch: ObjectIdentifier?

  /// **The whole keyboard is one touch target, and this is why.**
  ///
  /// UIKit was not delivering touches that landed in the gaps between caps. Measured on a
  /// simulator on 2026-09-06 with a probe in `touchesBegan`: taps across the q/w boundary
  /// at x = 40, 42, 44 and 46 points produced two `began` events, at 40 and at 46, and
  /// nothing at all at 42 and 44 — which is exactly the 6pt the drawn caps leave between
  /// them. Nine such gaps per row, plus the gaps between rows. Reported the same morning
  /// as "dead zones where tapping doesn't trigger a key ... Every tap should trigger a key
  /// press", and it produced no character, no preview and no highlight, because all three
  /// hang off a touch that never arrived.
  ///
  /// The resolution was never the problem: `KeyboardGeometry.hitTest` assigns every
  /// coordinate in the keyboard to a key, and `everyPointOnTheKeyboardResolvesToAKey`
  /// sweeps every point at 1pt spacing to prove it. The problem was that UIKit decided
  /// which view should hear about the touch before any of that ran.
  ///
  /// So this view stops asking. It claims every point inside its own bounds, and no cap,
  /// spacer, label, stack view or anything added to it later can take one — which is the
  /// difference between a keyboard that currently has no dead zones and one that cannot
  /// have them. The globe is the single exception and it is a real one: the keyboard list
  /// is only reachable through `handleInputModeList(from:with:)`, which wants the touch
  /// event UIKit hands a `UIControl`, so that control keeps the touches over its own cap.
  ///
  /// **This override is necessary and it is not sufficient**, which cost a whole build to
  /// learn: 0.0.6 shipped with it and the gaps were still dead. A keyboard extension's
  /// view is drawn in this process and composited by another one, and that other process
  /// decides which touches are worth forwarding before any code here runs. It decides by
  /// what was drawn. A region this view leaves fully transparent is not a region a finger
  /// can reach, so the override was answering a question it was never asked. `touchableFill`
  /// is the other half of the fix; neither half works alone.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard bounds.contains(point) else { return nil }
    if globeControl.isUserInteractionEnabled, globeControl.frame.contains(point) {
      return globeControl
    }
    return self
  }

  /// The one place a coordinate becomes a meaning.
  ///
  /// Nothing else in this view is allowed to ask whether a point is inside a rectangle.
  /// That is the invariant behind his rule: a tap cannot resolve to a key and also fail to
  /// light it or preview it, because the resolution happens once and the lighting, the
  /// preview and the insertion are all downstream of the same answer.
  private func target(at point: CGPoint) -> Target? {
    if point.y < StockMetrics.suggestionBarHeight {
      let slot = min(2, max(0, Int(point.x / (bounds.width / 3))))
      return .bubble(slot)
    }
    return geometry?.hitTest(point).map(Target.key)
  }

  /// **Every finger gets a target. This view used to answer only the first one.**
  ///
  /// `isMultipleTouchEnabled` defaults to false, and UIKit's documented behaviour for a
  /// view with it off is to deliver the first touch of a multi-touch sequence and ignore
  /// every other touch entirely — they are never reported, in any phase. Typing at speed
  /// is a multi-touch sequence almost continuously: the next finger lands before the last
  /// one lifts. So at speed this keyboard silently discarded taps, and the faster the
  /// typing the more it discarded.
  ///
  /// The evidence is what his phone produced while he typed "No: we do need an emoji key":
  ///
  ///     No; we ill med n moo key uh thiskeyboars nhchbdhHhhhf
  ///
  /// and, typing faster and crosser a few minutes later:
  ///
  ///     Oh f*tho codes goon to b a itaowhen rvowtsisnt i
  ///
  /// The lost `a` of "an", the lost `e` of "need", the lost space of "this keyboard" are
  /// taps that were never delivered. What is left is a mangled literal, and the corrector
  /// then rewrites it into real words — "need" to "med", "do" to "ill" — so the dropped
  /// taps and the bad corrections he reported the night before are one defect and not two.
  /// The second sample is much the heavier of the two, which is what loss rising with
  /// typing speed looks like; two samples is an observation and not a measurement.
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      guard let target = target(at: touch.location(in: self)) else { continue }
      held[ObjectIdentifier(touch)] = target
      press(target, touch: touch)
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      release(touch)
      guard let target = target(at: touch.location(in: self)) else { continue }
      switch target {
      case .key(let key):
        // The point is passed on untouched. Rounding it to the key here would throw away
        // the only signal the matcher runs on.
        onKey?(key, touch.location(in: self))
      case .bubble(let slot):
        if let text = bubbleText(slot) { onBubble?(text) }
      }
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches { release(touch) }
    if held.isEmpty {
      // A cancellation can arrive for a touch this view never recorded, so the whole
      // plate is put back rather than only the keys it remembers holding down.
      for key in geometry?.keys ?? [] {
        keyViews[key.id]?.backgroundColor = Self.restingColor(for: key, appearance: returnAppearance)
      }
    }
  }

  /// Everything a finger going down does, in one place.
  private func press(_ target: Target, touch: UITouch) {
    guard case .key(let key) = target else { return }
    keyViews[key.id]?.backgroundColor = Self.pressedKeyColor
    if key.role == .delete, deleteRepeatTouch == nil {
      deleteRepeatTouch = ObjectIdentifier(touch)
      startDeleteRepeat(for: key)
    }
    guard let letter = key.letter else { return }
    let view = preview(for: touch)
    view.show(
      String(isShifted ? Character(String(letter).uppercased()) : letter),
      in: previewFrame(above: key),
      capHeight: key.frame.height,
      capWidth: key.frame.width)
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

  /// Un-presses whatever this finger was holding and gives up its delete repeat. The key
  /// released is the one the finger went *down* on, which is not always the one it comes
  /// up over: a finger that slides between keys leaves the first one lit otherwise.
  private func release(_ touch: UITouch) {
    let id = ObjectIdentifier(touch)
    dismissPreview(for: touch)
    if case .key(let key)? = held.removeValue(forKey: id) {
      keyViews[key.id]?.backgroundColor = Self.restingColor(for: key, appearance: returnAppearance)
    }
    if deleteRepeatTouch == id {
      deleteRepeatTouch = nil
      stopDeleteRepeat()
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
  /// What the keyboard fills its own plate with so that the plate can be touched.
  ///
  /// This is one colour with one job, and the job is not colour. A keyboard extension
  /// draws in its own process and is composited by another one, and that other process
  /// decides which touches to forward on the strength of what was drawn: a region left
  /// fully transparent is never offered to this process at all, so no amount of hit
  /// testing here can reach it. `hitTest(_:with:)` claiming every point and this fill
  /// covering every point are the same statement made to the two halves of the system,
  /// and the keyboard is only whole when both are made.
  ///
  /// Measured on the simulator, 2026-09-06, taps at x = 30, 34, 38, 40, 42, 44, 46, 50
  /// across the q/w boundary with a probe on the first line of `hitTest`:
  ///
  ///     no fill        six of eight arrive; 42 and 44 never call `hitTest` at all
  ///     `.clear`       six of eight; alpha 0 is the same as no fill
  ///     alpha 1/255    eight of eight, `hitTest` and `touchesBegan` both
  ///
  /// So the alpha is the smallest an eight-bit framebuffer can hold that is not
  /// transparent, which is the whole of the reasoning behind the number: any larger value
  /// would be paint, and this keyboard deliberately does not paint its plate. iOS already
  /// draws the material behind it, that material is the correct colour to within nothing
  /// on both backdrops and in both appearances, and painting a constant over it is the
  /// mistake `KeyboardViewController.clearThePlate` exists to undo. SPEC.md Appendix A.11
  /// for that measurement; the black is arbitrary and only the alpha is load-bearing.
  static let touchableFill = UIColor(white: 0, alpha: 1.0 / 255.0)

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
/// The bubble that rises from a key while a finger is on it.
///
/// It is a shape rather than a rounded label, because stock's is a teardrop: a bulb above
/// the key joined to it by a narrower stem, so the two read as one object rather than as
/// a rectangle floating over another rectangle. The proportions are measured and live in
/// `StockMetrics.preview…InCaps`; this draws them.
///
/// One of these belongs to one finger. See `KeyboardView.previews` for why that is the
/// unit, which is a story about a bug that was holding another bug up.
final class KeyPreview: UIView {
  private let label = UILabel()
  private let shape = CAShapeLayer()
  private var capHeight: CGFloat = 0
  private var capWidth: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    shape.fillColor = KeyboardView.capColor.cgColor
    layer.addSublayer(shape)
    label.textAlignment = .center
    label.textColor = KeyboardView.keyTextColor
    addSubview(label)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Puts this preview over a key, with the letter that key is currently drawing.
  ///
  /// The cap's size comes in rather than being derived from the frame, because the frame
  /// is clamped on the top row and the shape has to keep its proportions when it is.
  func show(_ text: String, in frame: CGRect, capHeight: CGFloat, capWidth: CGFloat) {
    self.capHeight = capHeight
    self.capWidth = capWidth
    label.text = text
    self.frame = frame
    setNeedsLayout()
    layoutIfNeeded()
    isHidden = false
  }

  /// The whole outline, in one path: a bulb with soft shoulders whose sides draw in to
  /// meet the cap it belongs to.
  ///
  /// Drawn by hand rather than assembled out of rounded rectangles because stock's is not
  /// two shapes. A bulb plus a parallel stem leaves a step where they meet and is 14px too
  /// wide per side by the time it reaches the cap; see `StockMetrics.previewTaperTopInCaps`
  /// for what was measured and what is approximated.
  private func teardrop() -> UIBezierPath {
    let capTop = bounds.maxY - capHeight
    let taperTop = capTop - capHeight * StockMetrics.previewTaperTopInCaps
    let taperBottom = capTop + capHeight * StockMetrics.previewTaperBottomInCaps
    let pull = capHeight * StockMetrics.previewTaperPullInCaps
    let capLeft = bounds.midX - capWidth / 2
    let capRight = bounds.midX + capWidth / 2
    // The shoulders cannot be rounder than the straight part of the side is long, which
    // is what would happen if a phone ever gave the preview less room than it wants.
    let shoulder = min(
      StockMetrics.previewBulbCornerRadius, (taperTop - bounds.minY) / 2, bounds.width / 2)
    let foot = min(StockMetrics.capCornerRadius, capWidth / 2)

    let path = UIBezierPath()
    path.move(to: CGPoint(x: bounds.minX, y: bounds.minY + shoulder))
    path.addArc(
      withCenter: CGPoint(x: bounds.minX + shoulder, y: bounds.minY + shoulder),
      radius: shoulder, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
    path.addLine(to: CGPoint(x: bounds.maxX - shoulder, y: bounds.minY))
    path.addArc(
      withCenter: CGPoint(x: bounds.maxX - shoulder, y: bounds.minY + shoulder),
      radius: shoulder, startAngle: .pi * 1.5, endAngle: 0, clockwise: true)
    path.addLine(to: CGPoint(x: bounds.maxX, y: taperTop))
    path.addCurve(
      to: CGPoint(x: capRight, y: taperBottom),
      controlPoint1: CGPoint(x: bounds.maxX, y: taperTop + pull),
      controlPoint2: CGPoint(x: capRight, y: taperBottom - pull))
    // The bottom of the preview lies over the cap, so it ends the shape the cap does.
    path.addLine(to: CGPoint(x: capRight, y: bounds.maxY - foot))
    path.addArc(
      withCenter: CGPoint(x: capRight - foot, y: bounds.maxY - foot),
      radius: foot, startAngle: 0, endAngle: .pi * 0.5, clockwise: true)
    path.addLine(to: CGPoint(x: capLeft + foot, y: bounds.maxY))
    path.addArc(
      withCenter: CGPoint(x: capLeft + foot, y: bounds.maxY - foot),
      radius: foot, startAngle: .pi * 0.5, endAngle: .pi, clockwise: true)
    path.addLine(to: CGPoint(x: capLeft, y: taperBottom))
    path.addCurve(
      to: CGPoint(x: bounds.minX, y: taperTop),
      controlPoint1: CGPoint(x: capLeft, y: taperBottom - pull),
      controlPoint2: CGPoint(x: bounds.minX, y: taperTop + pull))
    path.close()
    return path
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    shape.path = teardrop().cgPath
    shape.fillColor = KeyboardView.capColor.resolvedColor(with: traitCollection).cgColor

    // The letter is drawn at stock's size, half again the size of the one on the cap, and
    // centred in a box measured down from the top of the preview rather than in any part
    // of the shape. See `StockMetrics.previewLetterBoxInCaps`.
    label.font = .systemFont(ofSize: StockMetrics.previewLetterPointSize)
    label.textColor = KeyboardView.keyTextColor.resolvedColor(with: traitCollection)
    label.frame = CGRect(
      x: 0, y: 0, width: bounds.width,
      height: capHeight * StockMetrics.previewLetterBoxInCaps)
  }
}

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
