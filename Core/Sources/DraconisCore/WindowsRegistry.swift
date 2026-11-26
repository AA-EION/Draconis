#if os(Windows)
import WinSDK

/// Reading string values from the Windows registry.
public enum WindowsRegistry {
    public enum Hive { case currentUser, localMachine }

    public static func string(_ hive: Hive, _ subkey: String, _ value: String) -> String? {
        let root: HKEY = hive == .currentUser ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE
        var size: DWORD = 0
        let flags = DWORD(RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ)
        guard subkey.withCString(encodedAs: UTF16.self, { key in
            value.withCString(encodedAs: UTF16.self) { name in
                RegGetValueW(root, key, name, flags, nil, nil, &size)
            }
        }) == ERROR_SUCCESS, size > 0 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(size) / MemoryLayout<WCHAR>.size + 1)
        guard subkey.withCString(encodedAs: UTF16.self, { key in
            value.withCString(encodedAs: UTF16.self) { name in
                RegGetValueW(root, key, name, flags, nil, &buffer, &size)
            }
        }) == ERROR_SUCCESS else { return nil }
        return String(decodingCString: buffer, as: UTF16.self)
    }
}
#endif
