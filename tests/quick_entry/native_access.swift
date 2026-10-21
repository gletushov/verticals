import Cocoa
import Carbon
import WebKit

@main struct AccessCheck {
    static func main() {
        _ = NSApplication.shared
        let state=URL(fileURLWithPath:"/tmp/quick-entry-access-check")
        try! FileManager.default.createDirectory(at:state,withIntermediateDirectories:true)
        try! Data("{\"binding\":\"cmd+shift\"}".utf8).write(to:state.appendingPathComponent("quick-entry-binding.json"))
        let entry=QuickEntry(state:state,base:URL(string:"http://127.0.0.1:8388/")!,web:WKWebView())
        assert(entry.fallbackHotkey != nil,"Fallback must register without Accessibility")
        assert(entry.read("quick-entry-status.json")?["fallback_registered"] as? Bool == true)
        var event: EventRef?
        CreateEvent(nil,OSType(kEventClassKeyboard),UInt32(kEventHotKeyPressed),0,0,&event)
        var id=EventHotKeyID(signature:0x56545145,id:2)
        SetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),
                          MemoryLayout<EventHotKeyID>.size,&id)
        SendEventToEventTarget(event,GetApplicationEventTarget())
        assert(entry.panel.isVisible,"Carbon hotkey event must open the bubble")
        ReleaseEvent(event)
        entry.close(cancel:true)
        assert(entry.register("cmd+shift+key:49") == nil,"Fallback can become the configured shortcut")
        assert(entry.hotkey != nil && entry.fallbackHotkey == nil)
        assert(entry.register("ctrl+alt+key:49") == nil,"A custom chord replaces it")
        print("Carbon fallback registered and opened the panel; rebind passed. Accessibility:",AXIsProcessTrusted())
    }
}
