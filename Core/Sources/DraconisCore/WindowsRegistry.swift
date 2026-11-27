#if os(Windows)
import WinSDK

/// Reading string values from the Windows registry.
public enum WindowsRegistry {
    public enum Hive { case currentUser, localMachine }

    public static func string(_ hive: Hive, _ subkey: String, _ value: String) -> String? {
        // HKEY_CURRENT_USER / HKEY_LOCAL_MACHINE are casts Swift can't import.
        let root = HKEY(bitPattern: UInt(hive == .currentUser ? 0x8000_0001 : 0x8000_0002))
        let flags = DWORD(0x0000_0002 | 0x0000_0004) // RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ
        var size: DWORD = 0
        let first = subkey.withCString(encodedAs: UTF16.self) { key in
            value.withCString(encodedAs: UTF16.self) { name in
                RegGetValueW(root, key, name, flags, nil, nil, &size)
            }
        }
        guard first == 0, size > 0 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(size) / MemoryLayout<WCHAR>.size + 1)
        let second = subkey.withCString(encodedAs: UTF16.self) { key in
            value.withCString(encodedAs: UTF16.self) { name in
                buffer.withUnsafeMutableBytes { bytes in
                    RegGetValueW(root, key, name, flags, nil, bytes.baseAddress, &size)
                }
            }
        }
        guard second == 0 else { return nil }
        return String(decodingCString: buffer, as: UTF16.self)
    }
}
#endif
