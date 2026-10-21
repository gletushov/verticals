import Cocoa
import Carbon
import WebKit

final class EntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class EntryText: NSTextView {
    var submit: (() -> Void)?
    var cancel: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { submit?(); return }
        super.keyDown(with: event)
    }
}

final class QuickEntry: NSObject {
    let state: URL
    let base: URL
    let mainWeb: WKWebView
    var panel: EntryPanel!
    var input = EntryText()
    var message = NSTextField(labelWithString: "")
    var saveButton: NSButton!
    var agentButton: NSButton!
    var previous: NSRunningApplication?
    var busy = false
    var captureID = UUID().uuidString
    var captureText = ""
    var captureAction = ""
    var binding = "fn"
    var hotkey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var globalMonitor: Any?
    var localMonitor: Any?
    var tap = FnTap()
    var timer: Timer?
    var lastRequest = ""

    init(state: URL, base: URL, web: WKWebView) {
        self.state = state; self.base = base; self.mainWeb = web
        super.init()
        buildPanel()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let entry = Unmanaged<QuickEntry>.fromOpaque(pointer).takeUnretainedValue()
            entry.show(); return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let saved = read("quick-entry-binding.json")?["binding"] as? String ?? "fn"
        if saved == "fn" && !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        let error = register(saved)
        status(request: "", error: error)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
    }

    func read(_ name: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: state.appendingPathComponent(name)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    func write(_ name: String, _ value: [String: Any]) {
        try? FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            try? data.write(to: state.appendingPathComponent(name), options: .atomic)
        }
    }
    func status(request: String, error: String?) {
        write("quick-entry-status.json", ["request": request, "binding": binding,
              "registered": hotkey != nil || globalMonitor != nil, "applied": error == nil, "error": error ?? "",
              "accessibility": AXIsProcessTrusted()])
    }
    func poll() {
        if binding == "fn" && globalMonitor == nil && AXIsProcessTrusted() {
            status(request: lastRequest, error: register("fn"))
        }
        guard let request = read("quick-entry-request.json"), let id = request["id"] as? String,
              id != lastRequest, let value = request["binding"] as? String else { return }
        lastRequest = id
        let error = register(value)
        if error == nil { write("quick-entry-binding.json", ["binding": binding]) }
        status(request: id, error: error)
    }
    func register(_ value: String) -> String? {
        if value == "fn" && !AXIsProcessTrusted() {
            return "Fn needs Accessibility access for this app, then reapply fn. Menu Quick Entry works meanwhile."
        }
        if value == binding && (globalMonitor != nil || hotkey != nil) { return nil }
        var candidate: EventHotKeyRef?
        if value != "fn" {
            let parts = value.split(separator: "+").map(String.init)
            guard let last = parts.last, last.hasPrefix("key:"), let code = UInt32(last.dropFirst(4)), code <= 127 else {
                return "Unsupported key. Use fn or modifiers+key:code."
            }
            var mods: UInt32 = 0
            for part in parts.dropLast() {
                switch part {
                case "cmd": mods |= UInt32(cmdKey)
                case "ctrl": mods |= UInt32(controlKey)
                case "alt": mods |= UInt32(optionKey)
                case "shift": mods |= UInt32(shiftKey)
                default: return "Unsupported modifier"
                }
            }
            let result = RegisterEventHotKey(code, mods, EventHotKeyID(signature: 0x56545145, id: 1),
                                             GetApplicationEventTarget(), 0, &candidate)
            guard result == noErr else { return "Key registration failed (\(result)); previous binding kept." }
        }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        hotkey = candidate; globalMonitor = nil; localMonitor = nil; binding = value; tap = FnTap()
        if value == "fn" {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.event($0) }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.event(event); return event
            }
            if !AXIsProcessTrusted() { return "Fn needs Accessibility access for this app, then reapply fn. Menu Quick Entry works meanwhile." }
        }
        return nil
    }
    func event(_ event: NSEvent) {
        if event.type == .keyDown { tap.key(); return }
        let other = !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        if tap.flags(fn: event.modifierFlags.contains(.function), other: other) { show() }
    }
    func buildPanel() {
        panel = EntryPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 208),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: panel.frame)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        content.layer?.cornerRadius = 24
        panel.contentView = content
        input.isRichText = false; input.font = .systemFont(ofSize: 22)
        input.textColor = .white; input.insertionPointColor = .white; input.backgroundColor = .clear
        input.drawsBackground = false; input.textContainerInset = NSSize(width: 0, height: 8)
        input.isVerticallyResizable = true; input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.submit = { [weak self] in self?.send("inbox") }
        input.cancel = { [weak self] in self?.close(cancel: true) }
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 74, width: 552, height: 110))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.documentView = input
        input.frame = scroll.bounds
        content.addSubview(scroll)
        saveButton = NSButton(title: "В Inbox  ⌘↵", target: self, action: #selector(save))
        agentButton = NSButton(title: "Отправить агенту", target: self, action: #selector(agent))
        for (button, x, width) in [(saveButton!, 24.0, 150.0), (agentButton!, 190.0, 180.0)] {
            button.bezelStyle = .rounded; button.frame = NSRect(x: x, y: 30, width: width, height: 32)
            content.addSubview(button)
        }
        message.frame = NSRect(x: 26, y: 5, width: 550, height: 22)
        message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor
        content.addSubview(message)
    }
    @objc func show() {
        if panel.isVisible { panel.makeKey(); panel.makeFirstResponder(input); return }
        previous = NSWorkspace.shared.frontmostApplication
        panel.center(); panel.orderFrontRegardless(); panel.makeKey(); panel.makeFirstResponder(input)
        message.stringValue = "Записать мысль или поручить агенту"
    }
    func close(cancel: Bool) {
        guard !busy else { return }
        if cancel { input.string = ""; captureID = UUID().uuidString }
        panel.orderOut(nil)
        previous?.activate(options: [])
    }
    @objc func save() { send("inbox") }
    @objc func agent() { send("agent") }
    func send(_ action: String) {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        if text != captureText || action != captureAction {
            captureID = UUID().uuidString; captureText = text; captureAction = action
        }
        busy = true; saveButton.isEnabled = false; agentButton.isEnabled = false; input.isEditable = false
        message.stringValue = "Отправляем…"
        mainWeb.evaluateJavaScript("JSON.parse(localStorage.getItem('vt-chat:last-model-selection') || 'null')") { [weak self] selection, _ in
            guard let self else { return }
            var body: [String: Any] = ["request": self.captureID, "action": action, "text": text]
            if let selection = selection as? [String: Any] { body["settings"] = selection }
            var request = URLRequest(url: self.base.appendingPathComponent("__chat/quick-entry"))
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body); request.timeoutInterval = 30
            URLSession.shared.dataTask(with: request) { data, response, error in
                let result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
                DispatchQueue.main.async {
                    self.busy = false; self.saveButton.isEnabled = true; self.agentButton.isEnabled = true; self.input.isEditable = true
                    guard (response as? HTTPURLResponse)?.statusCode == 200, error == nil else {
                        self.message.stringValue = result["error"] as? String ?? "Не удалось отправить. Текст сохранён — попробуйте ещё раз."
                        return
                    }
                    let event: [String: Any] = ["result": result, "text": text, "selection": selection ?? NSNull()]
                    if let json = try? JSONSerialization.data(withJSONObject: event), let value = String(data: json, encoding: .utf8) {
                        self.mainWeb.evaluateJavaScript("window.dispatchEvent(new CustomEvent('verticals-quick-entry', {detail: \(value)}))", completionHandler: nil)
                    }
                    self.input.string = ""; self.captureID = UUID().uuidString; self.close(cancel: false)
                }
            }.resume()
        }
    }
}
