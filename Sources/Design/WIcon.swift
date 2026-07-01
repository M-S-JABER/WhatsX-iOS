import SwiftUI

// The Android app ships a custom line-icon set. On iOS the idiomatic equivalent
// is SF Symbols (same thin-line aesthetic, RTL-aware). This maps each design
// glyph name to an SF Symbol so screens read the same as the Android WIcons.
enum WIcon {
    case chat, call, chart, hub, settings
    case search, add, back, forward, more, send, attach, mic, emoji, bolt, template
    case pin, archive, check, checkDouble, clock, alert, image, doc, download, play
    case pause, info, phoneCall, callEnd, callIn, callOut, callMissed, mute, speaker
    case user, users, shield, key, bell, moon, sun, globe, logout, whatsapp
    case copy, refresh, edit, trash, filter, chevDown, chevUp, chevLeft, chevRight, close
    case eye, eyeOff, link, dollar, building, webhook, history, lang, palette, lock
    case star, flag, pdf, cloud, share, reply, openInNew, place, smartphone, photoCamera, stop

    /// SF Symbol name. `filled` picks the solid variant used by the active bottom-nav tab.
    func symbol(filled: Bool = false) -> String {
        switch self {
        case .chat: return filled ? "bubble.left.fill" : "bubble.left"
        case .call: return filled ? "phone.fill" : "phone"
        case .chart: return filled ? "chart.bar.fill" : "chart.bar"
        case .hub: return "point.3.connected.trianglepath.dotted"
        case .settings: return filled ? "gearshape.fill" : "gearshape"
        case .search: return "magnifyingglass"
        case .add: return "plus"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .more: return "ellipsis"
        case .send: return "paperplane.fill"
        case .attach: return "paperclip"
        case .mic: return "mic.fill"
        case .emoji: return "face.smiling"
        case .bolt: return filled ? "bolt.fill" : "bolt"
        case .template: return "doc.text"
        case .pin: return "pin.fill"
        case .archive: return "archivebox"
        case .check: return "checkmark"
        case .checkDouble: return "checkmark.circle"
        case .clock: return "clock"
        case .alert: return "exclamationmark.triangle"
        case .image: return "photo"
        case .doc: return "doc"
        case .download: return "square.and.arrow.down"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .info: return "info.circle"
        case .phoneCall: return "phone.fill"
        case .callEnd: return "phone.down.fill"
        case .callIn: return "phone.arrow.down.left"
        case .callOut: return "phone.arrow.up.right"
        case .callMissed: return "phone.arrow.down.left"
        case .mute: return "mic.slash.fill"
        case .speaker: return "speaker.wave.2.fill"
        case .user: return "person.fill"
        case .users: return "person.2.fill"
        case .shield: return "checkmark.shield.fill"
        case .key: return "key.fill"
        case .bell: return filled ? "bell.fill" : "bell"
        case .moon: return "moon.fill"
        case .sun: return "sun.max.fill"
        case .globe: return "globe"
        case .logout: return "rectangle.portrait.and.arrow.right"
        case .whatsapp: return "message.fill"
        case .copy: return "doc.on.doc"
        case .refresh: return "arrow.clockwise"
        case .edit: return "pencil"
        case .trash: return "trash"
        case .filter: return "line.3.horizontal.decrease.circle"
        case .chevDown: return "chevron.down"
        case .chevUp: return "chevron.up"
        case .chevLeft: return "chevron.left"
        case .chevRight: return "chevron.right"
        case .close: return "xmark"
        case .eye: return "eye"
        case .eyeOff: return "eye.slash"
        case .link: return "link"
        case .dollar: return "dollarsign.circle"
        case .building: return "building.2"
        case .webhook: return "arrow.triangle.branch"
        case .history: return "clock.arrow.circlepath"
        case .lang: return "character.bubble"
        case .palette: return "paintpalette"
        case .lock: return "lock.fill"
        case .star: return "star.fill"
        case .flag: return "flag.fill"
        case .pdf: return "doc.richtext"
        case .cloud: return "cloud"
        case .share: return "square.and.arrow.up"
        case .reply: return "arrowshape.turn.up.left"
        case .openInNew: return "arrow.up.right.square"
        case .place: return "mappin.and.ellipse"
        case .smartphone: return "iphone"
        case .photoCamera: return "camera.fill"
        case .stop: return "stop.fill"
        }
    }
}

extension Image {
    /// `Image(icon: .chat)` — outline; `Image(icon: .chat, filled: true)` — solid.
    init(icon: WIcon, filled: Bool = false) {
        self.init(systemName: icon.symbol(filled: filled))
    }
}
