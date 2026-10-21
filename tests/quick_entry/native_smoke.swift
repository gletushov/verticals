import Cocoa
import WebKit

@main struct Smoke {
    static var delegate: Probe!
    static func main() {
        let app = NSApplication.shared
        delegate = Probe(); app.delegate = delegate; app.run()
    }
}
final class Probe: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var entry: QuickEntry!
    var web: WKWebView!
    var timer: Timer?
    let output = URL(fileURLWithPath: "/tmp/quick-entry-evidence")
    func applicationDidFinishLaunching(_ note: Notification) {
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try! Data("{\"binding\":\"key:90\"}".utf8).write(to: output.appendingPathComponent("quick-entry-binding.json"))
        web = WKWebView(); web.navigationDelegate = self
        web.load(URLRequest(url: URL(string:"http://127.0.0.1:8388/")!))
        DispatchQueue.main.asyncAfter(deadline:.now()+40) { print("TIMEOUT"); exit(2) }
    }
    func picture(_ name: String) {
        let view = entry.panel.contentView!
        view.displayIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        entry = QuickEntry(state:output,base:URL(string:"http://127.0.0.1:8388/")!,web:web)
        entry.show(); entry.input.string = "Сделай тестовую заметку — это должно остаться в Inbox"
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            self.picture("input")
            let key = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,
                windowNumber:self.entry.panel.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
            self.entry.input.keyDown(with:key)
            self.timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in
                if !self.entry.busy {
                    self.timer?.invalidate()
                    guard self.entry.input.string.isEmpty && !self.entry.panel.isVisible else {
                        print("SAVE FAILED: \(self.entry.message.stringValue)"); exit(3)
                    }
                    print("Native Cmd+Enter saved and closed")
                    self.entry.show(); self.entry.input.string="Отменить эту заметку"
                    let esc=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,
                        windowNumber:self.entry.panel.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:53)!
                    self.entry.input.keyDown(with:esc)
                    assert(!self.entry.panel.isVisible && self.entry.input.string.isEmpty)
                    print("Native Escape cancelled and closed")
                    // A real connection failure leaves the user's text and the retry buttons.
                    self.entry = QuickEntry(state:self.output,base:URL(string:"http://127.0.0.1:1/")!,web:self.web)
                    self.entry.show(); self.entry.input.string="Текст должен сохраниться при ошибке"
                    self.entry.send("inbox")
                    self.timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in
                        if !self.entry.busy {
                            self.timer?.invalidate()
                            assert(self.entry.panel.isVisible && !self.entry.input.string.isEmpty)
                            self.picture("error")
                            print("Native failure retained text and retry; screenshots saved")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }
}
