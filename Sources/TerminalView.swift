import AppKit
import Foundation

/// NSView that hosts a single Ghostty terminal surface.
/// Handles keyboard, mouse, and text input, forwarding everything to libghostty.
class TerminalView: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?
    private var callbackContext: Unmanaged<SurfaceCallbackContext>?
    private var keyTextAccumulator: [String]?
    private var markedTextStorage = NSMutableAttributedString()
    private var trackingArea: NSTrackingArea?

    let surfaceId: UUID
    let tabId: UUID
    var workingDirectory: String?

    init(frame: NSRect, tabId: UUID, workingDirectory: String? = nil) {
        self.surfaceId = UUID()
        self.tabId = tabId
        self.workingDirectory = workingDirectory
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let surface { ghostty_surface_free(surface) }
        callbackContext?.release()
    }

    // MARK: - Surface lifecycle

    func createSurface() {
        guard surface == nil, let app = GhosttyManager.shared.app else { return }
        guard window != nil else { return }

        let ctx = SurfaceCallbackContext(view: self, surfaceId: surfaceId, tabId: tabId)
        let unmanagedCtx = Unmanaged.passRetained(ctx)
        callbackContext?.release()
        callbackContext = unmanagedCtx

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.userdata = unmanagedCtx.toOpaque()
        config.scale_factor = Double(window?.backingScaleFactor ?? 2.0)
        config.context = GHOSTTY_SURFACE_CONTEXT_TAB

        // Set working directory if provided (so new tabs open in the workspace's directory)
        let cWorkingDir = workingDirectory.flatMap { strdup($0) }
        config.working_directory = UnsafePointer(cWorkingDir)

        self.surface = ghostty_surface_new(app, &config)
        if let ptr = cWorkingDir { free(ptr) }

        guard let surface else {
            print("Failed to create ghostty surface")
            callbackContext?.release()
            callbackContext = nil
            return
        }

        let scale = window?.backingScaleFactor ?? 2.0
        ghostty_surface_set_content_scale(surface, scale, scale)
        updateSurfaceSize()

        if let screen = window?.screen ?? NSScreen.main,
           let displayID = screen.displayID, displayID != 0 {
            ghostty_surface_set_display_id(surface, displayID)
        }
    }

    func updateSurfaceSize() {
        guard let surface, window != nil else { return }
        let backing = convertToBacking(bounds)
        let w = UInt32(max(backing.width, 1))
        let h = UInt32(max(backing.height, 1))
        ghostty_surface_set_size(surface, w, h)
    }

    // MARK: - View lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if surface == nil && window != nil {
            createSurface()
        }
        updateTrackingAreas()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface, let window else { return }
        let scale = window.backingScaleFactor
        ghostty_surface_set_content_scale(surface, scale, scale)
        updateSurfaceSize()
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    // MARK: - First responder

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    // MARK: - Keyboard input

    override func keyDown(with event: NSEvent) {
        guard let surface else { super.keyDown(with: event); return }

        // Ensure focus
        ghostty_surface_set_focus(surface, true)

        // Accumulate text from interpretKeyEvents
        keyTextAccumulator = []
        interpretKeyEvents([event])

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = hasMarkedText()
        keyEvent.unshifted_codepoint = unshiftedCodepoint(for: event)

        // Use text from IME/interpretKeyEvents if available, otherwise from event
        let text = keyTextAccumulator?.first ?? event.characters ?? ""
        if text.isEmpty {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        } else {
            text.withCString { ptr in
                keyEvent.text = ptr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        }
        keyTextAccumulator = nil
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { super.keyUp(with: event); return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { super.flagsChanged(with: event); return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let fr = window?.firstResponder as? NSView,
              fr === self || fr.isDescendant(of: self) else { return false }
        guard let surface else { return false }

        // Check if Ghostty has a binding for this key
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = unshiftedCodepoint(for: event)

        let text = event.characters ?? ""
        var flags = ghostty_binding_flags_e(0)
        let isBinding = text.withCString { ptr in
            keyEvent.text = ptr
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }

        guard isBinding else { return false }

        // Send the key to Ghostty
        text.withCString { ptr in
            keyEvent.text = ptr
            _ = ghostty_surface_key(surface, keyEvent)
        }
        return true
    }

    // Prevent system beep on unhandled key commands
    override func doCommand(by selector: Selector) {}

    // MARK: - Mouse input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Update selected tab when clicking in a split pane
        NotificationCenter.default.post(name: .terminalViewDidFocus, object: self)
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, modsFromEvent(event))
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, modsFromEvent(event))
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, modsFromEvent(event))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, modsFromEvent(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, modsFromEvent(event))
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, modsFromEvent(event))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, pos.y, modsFromEvent(event))
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, modsFromEvent(event))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        let mods = ghostty_input_scroll_mods_t(modsFromEvent(event).rawValue)
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, mods)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let s = string as? String { text = s }
        else if let s = string as? NSAttributedString { text = s.string }
        else { return }
        markedTextStorage.mutableString.setString("")
        keyTextAccumulator?.append(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let s = string as? String {
            markedTextStorage.mutableString.setString(s)
        } else if let s = string as? NSAttributedString {
            markedTextStorage.setAttributedString(s)
        }

        if markedTextStorage.length > 0, let surface {
            let text = markedTextStorage.string
            text.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
            }
        } else if let surface {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func unmarkText() {
        markedTextStorage.mutableString.setString("")
        if let surface { ghostty_surface_preedit(surface, nil, 0) }
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        markedTextStorage.length > 0
            ? NSRange(location: 0, length: markedTextStorage.length)
            : NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedTextStorage.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewPoint = NSPoint(x: x, y: y)
        let screenPoint = window?.convertPoint(toScreen: convert(viewPoint, to: nil)) ?? viewPoint
        return NSRect(x: screenPoint.x, y: screenPoint.y - h, width: w, height: h)
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }

    // MARK: - Helpers

    private func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if event.modifierFlags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if event.modifierFlags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if event.modifierFlags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if event.modifierFlags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    private func unshiftedCodepoint(for event: NSEvent) -> UInt32 {
        guard let chars = event.charactersIgnoringModifiers ?? event.characters,
              let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20,
              !(scalar.value >= 0xF700 && scalar.value <= 0xF8FF) else { return 0 }
        return scalar.value
    }
}

extension Notification.Name {
    static let terminalViewDidFocus = Notification.Name("terminalViewDidFocus")
}

// MARK: - NSScreen extension

extension NSScreen {
    var displayID: UInt32? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return id.uint32Value
    }
}
