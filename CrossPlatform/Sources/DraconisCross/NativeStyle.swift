import DraconisCore
import Foundation
import SwiftCrossUI
#if canImport(GtkBackend)
import CGtk
import Gtk
import GtkBackend
#endif
#if canImport(WinUIBackend)
import WinUI
import WinUIBackend
import WinSDK
#endif

/// Native look on top of SwiftCrossUI: GTK CSS on Linux (blur on GTK 4.22+,
/// Orbitron for headings), Mica on Windows.
enum NativeStyle {
    static var resources: URL? { Bundle.module.resourceURL }

    #if canImport(GtkBackend)
    @MainActor static var provider: CSSProvider?

    @MainActor static func install() {
        guard provider == nil else { return }
        registerFonts()
        let blur = gtk_get_minor_version() >= 22
            ? "backdrop-filter: blur(18px) saturate(170%);" : ""
        let css = """
        window, .background { background-color: #0f1216; color: #eef1f4; }
        .draconis-glass {
            border-radius: 18px;
            box-shadow: inset 0 1px rgba(255,255,255,0.22), 0 8px 24px rgba(0,0,0,0.28);
            \(blur)
        }
        .draconis-hero { font-family: "Orbitron"; font-weight: 900; }
        button {
            border-radius: 999px; background-color: transparent;
            background-image: linear-gradient(to bottom, rgba(255,255,255,0.16), rgba(255,255,255,0.06));
            border: 1px solid rgba(255,255,255,0.18); color: #eef1f4;
            box-shadow: inset 0 1px rgba(255,255,255,0.25);
        }
        button:hover { background-image: linear-gradient(to bottom, rgba(255,255,255,0.24), rgba(255,255,255,0.10)); }
        window button.draconis-prominent, window button.draconis-prominent:hover,
        window .draconis-prominent button, window .draconis-prominent button:hover {
            background-image: linear-gradient(to bottom, #e6ebef, #c5ccd3); color: #101418; font-weight: 700;
        }
        entry { border-radius: 999px; background-color: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.16); }
        list, listview, row { background-color: transparent; }
        row:selected { background-color: rgba(209,216,222,0.18); border-radius: 10px; }
        switch:checked { background-color: #c5ccd3; }
        switch:checked slider { background-color: #101418; }
        progressbar trough { border-radius: 999px; background-color: rgba(255,255,255,0.08); }
        progressbar progress { border-radius: 999px; background-color: #d1d8de; }
        """
        let provider = CSSProvider()
        provider.loadCss(from: css)
        self.provider = provider
    }

    /// Make Orbitron available to Pango without installing it for the user.
    static func registerFonts() {
        guard let dir = resources,
              let lib = dlopen("libfontconfig.so.1", RTLD_NOW),
              let symbol = dlsym(lib, "FcConfigAppFontAddFile") else { return }
        typealias AddFont = @convention(c) (OpaquePointer?, UnsafePointer<UInt8>) -> Int32
        let add = unsafeBitCast(symbol, to: AddFont.self)
        for font in ["Orbitron-Black.ttf", "Orbitron-Bold.ttf"] {
            let path = dir.appendingPathComponent(font).path
            _ = path.withCString { $0.withMemoryRebound(to: UInt8.self, capacity: path.utf8.count + 1) { add(nil, $0) } }
        }
    }
    #elseif canImport(WinUIBackend)
    @MainActor static func install() {
        guard let dir = resources else { return }
        for font in ["Orbitron-Black.ttf", "Orbitron-Bold.ttf"] {
            let path = dir.appendingPathComponent(font).path
            _ = path.withCString(encodedAs: UTF16.self) { AddFontResourceExW($0, DWORD(0x10), nil) } // FR_PRIVATE
        }
    }
    #else
    @MainActor static func install() {}
    #endif
}

extension View {
    /// Add native style classes (GTK) — no-op elsewhere.
    @ViewBuilder
    func nativeClass(_ classes: String) -> some View {
        #if canImport(GtkBackend)
        self.inspect(.onCreate) { widget in
            for name in classes.split(separator: " ") {
                gtk_widget_add_css_class(widget.widgetPointer, String(name))
            }
        }
        #else
        self
        #endif
    }

    /// Window-wide setup: styles, fonts, and Mica on Windows.
    @ViewBuilder
    func nativeWindow() -> some View {
        #if canImport(GtkBackend)
        self.inspectWindow { _ in NativeStyle.install() }
        #elseif canImport(WinUIBackend)
        self.inspectWindow { window in
            NativeStyle.install()
            window.systemBackdrop = WinUI.MicaBackdrop()
        }
        #else
        self
        #endif
    }
}

extension SwiftCrossUI.Button {
    /// The bright "glassProminent" button.
    @MainActor @ViewBuilder
    func prominent() -> some View {
        #if canImport(GtkBackend)
        self.nativeClass("draconis-prominent")
        #else
        self
        #endif
    }
}
