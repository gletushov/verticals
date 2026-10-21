import Cocoa
import Carbon
import WebKit

final class EntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class QuickEntry: NSObject, WKScriptMessageHandler {
    let state: URL
    let base: URL
    let mainWeb: WKWebView
    var panel: EntryPanel!
    var entryWeb: WKWebView!
    var openMain: (() -> Void)?
    var previous: NSRunningApplication?
    var busy = false
    var captureID = UUID().uuidString
    var captureText = ""
    var captureAction = ""
    var binding = "cmd+shift"
    var hotkey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var globalMonitor: Any?
    var localMonitor: Any?
    var tap = ModifierTap(required: 6)
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
        let saved = read("quick-entry-binding.json")?["binding"] as? String ?? "cmd+shift"
        if !saved.contains("key:") && !AXIsProcessTrusted() {
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
              "accessibility": AXIsProcessTrusted(), "app_path": Bundle.main.bundlePath, "pid": ProcessInfo.processInfo.processIdentifier])
    }
    func poll() {
        if !binding.contains("key:") && globalMonitor == nil && AXIsProcessTrusted() {
            status(request: lastRequest, error: register(binding))
        }
        guard let request = read("quick-entry-request.json"), let id = request["id"] as? String,
              id != lastRequest, let value = request["binding"] as? String else { return }
        lastRequest = id
        let error = register(value)
        if error == nil { write("quick-entry-binding.json", ["binding": binding]) }
        status(request: id, error: error)
    }
    func register(_ value: String) -> String? {
        if !value.contains("key:") && !AXIsProcessTrusted() {
            return "Modifier-only shortcuts need Accessibility access for this running app. Quick Entry in the menu works meanwhile."
        }
        if value == binding && (globalMonitor != nil || hotkey != nil) { return nil }
        var candidate: EventHotKeyRef?
        if value.contains("key:") {
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
        hotkey = candidate; globalMonitor = nil; localMonitor = nil; binding = value; tap = ModifierTap(required: Self.mask(value))
        if !value.contains("key:") {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.event($0) }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.event(event); return event
            }
            if !AXIsProcessTrusted() { return "Modifier-only shortcuts need Accessibility access for this running app. Quick Entry in the menu works meanwhile." }
        }
        return nil
    }
    static func mask(_ binding: String) -> UInt {
        binding.split(separator: "+").reduce(0) { $0 | (["fn":UInt(1),"cmd":2,"shift":4,"ctrl":8,"alt":16][String($1)] ?? 0) }
    }
    func event(_ event: NSEvent) {
        if event.type == .keyDown { tap.key(); return }
        var mask: UInt = 0
        for (flag, bit): (NSEvent.ModifierFlags, UInt) in [(.function,1),(.command,2),(.shift,4),(.control,8),(.option,16)] {
            if event.modifierFlags.contains(flag) { mask |= bit }
        }
        if tap.flags(mask) { show() }
    }
    func buildPanel() {
        panel = EntryPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 84),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "quickEntry")
        entryWeb = WKWebView(frame: NSRect(x:0,y:0,width:600,height:84), configuration:config)
        entryWeb.setValue(false, forKey:"drawsBackground")
        entryWeb.autoresizingMask = [.width, .height]
        panel.contentView = entryWeb
        entryWeb.load(URLRequest(url:base.appendingPathComponent("quick-entry.html"), cachePolicy:.reloadIgnoringLocalCacheData))
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "resize", let height = body["height"] as? Double {
            let h = min(400, max(84, height))
            let frame = panel.frame
            panel.setFrame(NSRect(x:frame.minX,y:frame.maxY-h,width:frame.width,height:h),display:true)
        } else if action == "cancel" { close(cancel:true) }
        else if (action == "agent" || action == "inbox"), let text = body["text"] as? String { send(action, text:text) }
    }
    func ui(_ error: String = "", clear: Bool = false) {
        let args: [Any] = [busy,error,clear]
        if let data = try? JSONSerialization.data(withJSONObject:args), let json = String(data:data,encoding:.utf8) {
            entryWeb.evaluateJavaScript("window.quickEntry?.state(..."+json+")", completionHandler:nil)
        }
    }
    @objc func show() {
        if !panel.isVisible { previous = NSWorkspace.shared.frontmostApplication; panel.center() }
        panel.orderFrontRegardless(); panel.makeKey(); panel.makeFirstResponder(entryWeb)
        entryWeb.evaluateJavaScript("window.quickEntry?.focus()",completionHandler:nil)
    }
    func close(cancel: Bool, restore: Bool = true) {
        guard !busy else { return }
        if cancel { captureID = UUID().uuidString; ui(clear:true) }
        panel.orderOut(nil)
        if restore { previous?.activate(options: []) }
    }
    func send(_ action: String, text raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        if text != captureText || action != captureAction {
            captureID = UUID().uuidString; captureText = text; captureAction = action
        }
        busy = true; ui()
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
                    self.busy = false
                    guard (response as? HTTPURLResponse)?.statusCode == 200, error == nil else {
                        self.ui(result["error"] as? String ?? "Не удалось отправить. Текст сохранён — попробуйте ещё раз.")
                        return
                    }
                    if action == "agent", let goal = result["goal"] as? String {
                        let path = "#goal/" + goal
                        let encoded = try! JSONSerialization.data(withJSONObject:[path])
                        let args = String(data:encoded,encoding:.utf8)!
                        self.mainWeb.evaluateJavaScript("history.pushState(null,'',"+args+"[0]);window.dispatchEvent(new PopStateEvent('popstate'))",completionHandler:nil)
                        self.openMain?()
                    }
                    if let error = result["error"] as? String {
                        self.ui("Задача сохранена. " + error + " Повтори ⌘Enter для запуска агента.")
                        self.show()
                        return
                    }
                    let event: [String: Any] = ["result": result, "text": text, "selection": selection ?? NSNull()]
                    if let json = try? JSONSerialization.data(withJSONObject: event), let value = String(data: json, encoding: .utf8) {
                        self.mainWeb.evaluateJavaScript("window.dispatchEvent(new CustomEvent('verticals-quick-entry', {detail: \(value)}))", completionHandler: nil)
                    }
                    self.ui(clear:true); self.captureID = UUID().uuidString; self.close(cancel: false, restore:action == "inbox")
                    if action == "agent" { self.openMain?() }
                }
            }.resume()
        }
    }
}
