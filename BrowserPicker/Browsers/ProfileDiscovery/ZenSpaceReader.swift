import Compression
import Foundation

/// Reads the spaces of one Zen profile from `zen-sessions.jsonlz4`, the session
/// file Zen writes next to Firefox's own session store. Order matters: it is the
/// order Zen shows in its Spaces menu.
enum ZenSpaceReader {
    private static let sessionFileNames = [
        "zen-sessions.jsonlz4",
        "zen-sessions-backup/recovery.jsonlz4",
        "zen-sessions-backup/clean.jsonlz4"
    ]

    static func spaces(inProfileAt profilePath: String) -> [BrowserSpace] {
        let profileURL = URL(fileURLWithPath: profilePath)
        let containerNames = ZenContainerReader.namesByContextId(inProfileAt: profileURL)

        for name in sessionFileNames {
            let spaces = spaces(
                inSessionFileAt: profileURL.appendingPathComponent(name),
                containerNames: containerNames
            )
            if !spaces.isEmpty { return spaces }
        }
        return []
    }

    private static func spaces(
        inSessionFileAt url: URL,
        containerNames: [Int: String]
    ) -> [BrowserSpace] {
        guard let json = MozLz4.decode(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let entries = root["spaces"] as? [[String: Any]]
        else { return [] }

        return entries.compactMap { entry in
            guard let uuid = entry["uuid"] as? String, !uuid.isEmpty else { return nil }
            let name = (entry["name"] as? String) ?? ""
            let contextId = (entry["containerTabId"] as? Int) ?? 0

            return BrowserSpace(
                id: uuid,
                name: name.isEmpty ? "Space" : name,
                containerName: containerNames[contextId]
            )
        }
    }
}

/// Reads the containers — Gecko's contextual identities — of one profile, so a
/// space can name the container it opens its tabs in.
enum ZenContainerReader {
    /// The four containers Gecko ships carry a localisation id instead of a
    /// name; these are the labels the browser shows for them in English.
    private static let builtInNames = [
        "user-context-personal": "Personal",
        "user-context-work": "Work",
        "user-context-banking": "Banking",
        "user-context-shopping": "Shopping"
    ]

    static func namesByContextId(inProfileAt profileURL: URL) -> [Int: String] {
        let url = profileURL.appendingPathComponent("containers.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let identities = root["identities"] as? [[String: Any]]
        else { return [:] }

        var names: [Int: String] = [:]
        for identity in identities {
            // Gecko hides its internal identities, which are no user's choice.
            guard (identity["public"] as? Bool) ?? true,
                  let contextId = identity["userContextId"] as? Int
            else { continue }

            if let name = identity["name"] as? String, !name.isEmpty {
                names[contextId] = name
            } else if let l10nId = identity["l10nId"] as? String,
                      let name = builtInNames[l10nId] {
                names[contextId] = name
            }
        }
        return names
    }
}

/// Mozilla's `mozLz4` container: an 8-byte magic, the decompressed size as a
/// little-endian `UInt32`, then a raw LZ4 block — which is exactly what
/// `COMPRESSION_LZ4_RAW` decodes.
enum MozLz4 {
    private static let magic = Array("mozLz4".utf8)
    private static let headerSize = 12

    static func decode(contentsOf url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count > headerSize else { return nil }
        let bytes = [UInt8](data)
        guard Array(bytes.prefix(magic.count)) == magic else { return nil }

        let size = bytes[8..<headerSize]
            .enumerated()
            .reduce(UInt32(0)) { total, byte in total | (UInt32(byte.element) << (8 * UInt32(byte.offset))) }
        guard size > 0 else { return nil }

        let payload = Array(bytes[headerSize...])
        var output = Data(count: Int(size))
        let written = output.withUnsafeMutableBytes { destination in
            payload.withUnsafeBufferPointer { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    Int(size),
                    source.baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }

        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}
