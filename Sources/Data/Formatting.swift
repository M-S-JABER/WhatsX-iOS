import Foundation
import UniformTypeIdentifiers

// Central date/format helpers — every screen parses the backend's ISO
// timestamps through here (several screens used to carry private copies).

func dayLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return L("اليوم") }
    if cal.isDateInYesterday(date) { return L("أمس") }
    let f = DateFormatter()
    f.locale = L10n.dateLocale
    f.dateFormat = "d MMMM yyyy"
    return f.string(from: date)
}

// Formatters are expensive to create and these run per row per render —
// build them once. All call sites are on the main actor.
private let isoFractionalParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlainParser = ISO8601DateFormatter()
private let clockFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
}()

func parseISODate(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    return isoFractionalParser.date(from: iso) ?? isoPlainParser.date(from: iso)
}

func clockTime(_ iso: String?) -> String {
    guard let date = parseISODate(iso) else { return "" }
    return clockFormatter.string(from: date)
}

private let dayMonthFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "dd/MM"; return f
}()
private let dayClockFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "d/M HH:mm"; return f
}()

/// Very small relative-time formatter for list rows: "HH:mm" today,
/// "أمس" yesterday, otherwise "dd/MM".
func shortTime(_ iso: String?) -> String {
    guard let date = parseISODate(iso) else { return "" }
    let cal = Calendar.current
    if cal.isDateInToday(date) { return clockFormatter.string(from: date) }
    if cal.isDateInYesterday(date) { return L("أمس") }
    return dayMonthFormatter.string(from: date)
}

/// "d/M HH:mm" — monitor/log timestamps.
func dayClockTime(_ iso: String?) -> String {
    guard let date = parseISODate(iso) else { return "" }
    return dayClockFormatter.string(from: date)
}

func mimeType(for url: URL) -> String {
    UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
}
