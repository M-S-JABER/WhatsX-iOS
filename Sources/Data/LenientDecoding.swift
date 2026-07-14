import Foundation

// Lenient decoding utilities. The backend's JSON shapes drift (free-form
// metadata, optional columns, per-event payloads), and a single unexpected
// field must never sink a whole screen. These helpers make that the default:
//   - LossyArray drops malformed ELEMENTS instead of failing the array.
//   - KeyedDecodingContainer.lenient/lossy tolerate missing keys, nulls and
//     type mismatches, falling back to a default.

/// Decodes each element independently; elements that fail to decode are
/// skipped rather than failing the whole array.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element] = []

    /// Consumes (and discards) one arbitrary value to advance the container.
    private struct Blackhole: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init() {}

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else { return }
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Blackhole.self)
            }
        }
    }
}

extension KeyedDecodingContainer {
    /// Array field that tolerates a missing key, null, a non-array value,
    /// and malformed individual elements (which are dropped).
    func lossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        ((try? decodeIfPresent(LossyArray<T>.self, forKey: key)) ?? nil)?.elements ?? []
    }

    /// Optional field that tolerates a missing key, null, or a type mismatch.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Defaulted field that tolerates a missing key, null, or a type mismatch.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default def: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? def
    }
}

extension Error {
    /// One canonical human-readable message for any thrown error.
    var apiMessage: String {
        (self as? ApiError)?.message ?? localizedDescription
    }
}
