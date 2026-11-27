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
#endif

/// Native look on top of SwiftCrossUI: GTK CSS with the bundled fonts on
/// Linux (blur on GTK 4.22+), Mica on Windows.
enum NativeStyle {
    static var resources: URL? { Bundle.module.resourceURL }
    static let fonts = ["Orbitron-Black.ttf", "Orbitron-Bold.ttf", "Inter.ttf",
                        "BarlowCondensed-Bold.ttf", "BarlowCondensed-SemiBold.ttf"]

    #if canImport(GtkBackend)
    @MainActor static var provider: CSSProvider?

    @MainActor static func install() {
        guard provider == nil else { return }
        registerFonts()
        let blur = gtk_get_minor_version() >= 22
            ? "backdrop-filter: blur(18px) saturate(170%);" : ""
        let css = """
        window, .background { background-color: #0f1216; color: #eef1f4; }
        window, label, entry, button, text { font-family: "Inter", "Cantarell", sans-serif; }
        .draconis-glass {
            border-radius: 18px;
            box-shadow: inset 0 1px rgba(255,255,255,0.22), 0 8px 24px rgba(0,0,0,0.28);
            \(blur)
        }
        .draconis-hero, .draconis-hero label { font-family: "Orbitron"; font-weight: 900; }
        .draconis-display, .draconis-display label { font-family: "Orbitron"; font-weight: 700; }
        .draconis-title, .draconis-title label { font-family: "Barlow Condensed"; font-weight: 700; }
        .draconis-stencil, .draconis-stencil label { font-family: "Barlow Condensed"; font-weight: 700; letter-spacing: 0; }
        button:not(.flat) {
            border-radius: 999px; background-color: transparent;
            background-image: linear-gradient(to bottom, rgba(255,255,255,0.16), rgba(255,255,255,0.06));
            border: 1px solid rgba(255,255,255,0.18); color: #eef1f4;
            box-shadow: inset 0 1px rgba(255,255,255,0.25);
        }
        button:not(.flat):hover { background-image: linear-gradient(to bottom, rgba(255,255,255,0.24), rgba(255,255,255,0.10)); }
        button.flat, button.flat:hover, button.flat:active, button.flat:focus {
            background: none; border: none; box-shadow: none; outline: none;
            padding: 0; margin: 0; min-height: 0; min-width: 0;
        }
        entry { border-radius: 999px; background-color: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.16); }
        list, listview, row { background-color: transparent; }
        row:selected { background-color: rgba(209,216,222,0.18); border-radius: 10px; }
        switch:checked { background-color: #c5ccd3; }
        switch:checked slider { background-color: #101418; }
        progressbar trough { border-radius: 999px; background-color: rgba(255,255,255,0.08); min-height: 8px; }
        progressbar progress { border-radius: 999px; background-color: #d1d8de; min-height: 8px; }
        scrollbar { background: transparent; }
        """
        // Window icon, also for the AppImage and tarball, whose icon isn't in the theme.
        if let display = gdk_display_get_default(), let dir = resources?.appendingPathComponent("appicon").path {
            gtk_icon_theme_add_search_path(gtk_icon_theme_get_for_display(display), dir)
        }
        gtk_window_set_default_icon_name(AppInfo.appID)
        let provider = CSSProvider()
        provider.loadCss(from: css)
        self.provider = provider
    }

    /// Make the bundled fonts available to Pango without installing them.
    static func registerFonts() {
        guard let dir = resources,
              let lib = dlopen("libfontconfig.so.1", RTLD_NOW),
              let symbol = dlsym(lib, "FcConfigAppFontAddFile") else { return }
        typealias AddFont = @convention(c) (OpaquePointer?, UnsafePointer<UInt8>) -> Int32
        let add = unsafeBitCast(symbol, to: AddFont.self)
        for font in NativeStyle.fonts {
            let path = dir.appendingPathComponent(font).path
            _ = path.withCString { $0.withMemoryRebound(to: UInt8.self, capacity: path.utf8.count + 1) { add(nil, $0) } }
        }
    }
    #elseif canImport(WinUIBackend)
    // WinUI measures every Text with one default-font TextBlock, so a custom
    // family would be clipped: Windows keeps Segoe UI Variable.
    @MainActor static func install() {}
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
            window.systemBackdrop = WinUI.MicaBackdrop()
        }
        #else
        self
        #endif
    }
}
