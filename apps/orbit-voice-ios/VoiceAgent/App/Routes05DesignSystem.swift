import SwiftUI

/// ROUTES 05 is an additive presentation layer. It owns visual tokens and
/// reusable wayfinding primitives; feature stores and navigation remain in
/// their existing views.
enum Routes05Tokens {
    static let canvas = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "111815" : "F4F3E9")
    })
    static let surface = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "202923" : "FFFFFF")
    })
    static let ink = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "F5F5E9" : "161D1B")
    })
    static let secondary = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "A9B6AC" : "656F69")
    })
    static let rule = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "45534B" : "C8CEC4")
    })
    static let yellow = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "E4EE54" : "F1F85B")
    })
    static let blue = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "9EAEFF" : "3D57ED")
    })
    static let orange = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "FF8368" : "FF6444")
    })
    static let mint = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "70DCC7" : "69DFC7")
    })
    static let lilac = Color(uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? "BFA9F2" : "C9B8FF")
    })

    /// Fixed contrast colors for authored ROUTES surfaces. Dynamic `ink` is
    /// intentionally not used here because it becomes near-white in dark mode.
    static let accentInk = Color(uiColor: UIColor(hex: "161D1B"))
    static let darkSurface = Color(uiColor: UIColor(hex: "161D1B"))
    static let darkSurfaceInk = Color(uiColor: UIColor(hex: "F5F5E9"))

    static func foreground(on accent: Color) -> Color { accentInk }
}
private extension UIColor {
    convenience init(hex: String) {
        let value = Int(hex, radix: 16) ?? 0
        self.init(red: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255,
                  alpha: 1)
    }
}

struct Routes05Mast: View {
    let section: String
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().stroke(Routes05Tokens.ink, lineWidth: 2)
                    Circle().fill(Routes05Tokens.mint).frame(width: 8, height: 8)
                }
                .frame(width: 27, height: 27)
                Text("orbit").font(.system(size: 20, weight: .black, design: .rounded)).tracking(-1.2)
            }
            Text("/ ROUTES").font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1.1)
            Spacer(minLength: 8)
            Text("\(section.uppercased()) / 05")
                .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1.1)
            if let action {
                Button(action: action) { Image(systemName: "ellipsis") }
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Routes05Tokens.ink)
                    .background(Routes05Tokens.surface)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.ink, lineWidth: 1.2))
                    .accessibilityLabel("Додаткові дії")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 49)
        .foregroundStyle(Routes05Tokens.ink)
        .overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.ink).frame(height: 1.5) }
    }
}

/// Shared root geometry. Keeping the text column and badge in one fixed-width
/// trailing slot prevents long localized titles from moving the badge left.
struct Routes05RootHeader<Badge: View>: View {
    let eyebrow: String
    let title: String
    let detail: String?
    let badge: Badge

    init(_ eyebrow: String, title: String, detail: String? = nil, @ViewBuilder badge: () -> Badge) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.badge = badge()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Routes05Tokens.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(title)
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .tracking(-1.8)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Routes05Tokens.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            badge
                .frame(width: 59, height: 59)
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

struct Routes05OrbitBadge: View {
    var body: some View {
        ZStack {
            Circle().stroke(Routes05Tokens.ink, lineWidth: 7).frame(width: 52, height: 52)
            Circle().fill(Routes05Tokens.yellow).frame(width: 30, height: 30)
        }
        .frame(width: 59, height: 59)
        .background(Routes05Tokens.mint, in: Circle())
        .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
        .accessibilityLabel("Orbit")
    }
}

struct Routes05SchoolBadge: View {
    let classLabel: String?

    var body: some View {
        Text(classLabel?.isEmpty == false ? classLabel! : "—")
            .font(.system(.headline, design: .rounded).weight(.black))
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .foregroundStyle(Routes05Tokens.accentInk)
            .frame(width: 59, height: 59)
            .background(Routes05Tokens.mint, in: Circle())
            .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
            .accessibilityLabel(classLabel?.isEmpty == false ? "Клас \(classLabel!)" : "Клас не визначено")
    }
}

struct Routes05Chapter: View {
    let eyebrow: String
    let title: String
    let detail: String?
    let accent: Color

    init(_ eyebrow: String, title: String, detail: String? = nil, accent: Color = Routes05Tokens.yellow) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail; self.accent = accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow).font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.4).foregroundStyle(Routes05Tokens.secondary)
                    Text(title).font(.system(.largeTitle, design: .rounded).weight(.black)).tracking(-1.8).lineLimit(nil)
                }
                Spacer(minLength: 8)
                Text("↗").font(.system(size: 27, weight: .black)).foregroundStyle(Routes05Tokens.accentInk)
                    .frame(width: 59, height: 59).background(accent).clipShape(Circle())
                    .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
            }
            if let detail { Text(detail).font(.subheadline).foregroundStyle(Routes05Tokens.secondary) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 3)
    }
}

struct Routes05Hero<Content: View>: View {
    let accent: Color
    let content: Content
    init(accent: Color = Routes05Tokens.yellow, @ViewBuilder content: () -> Content) { self.accent = accent; self.content = content() }
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent).clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.ink, lineWidth: 1.5))
            .shadow(color: Routes05Tokens.ink, radius: 0, x: 4, y: 4)
            .foregroundStyle(Routes05Tokens.accentInk)
            .padding(.horizontal, 16)
    }
}

struct Routes05Ticket<Content: View>: View {
    let tint: Color
    let index: String?
    let content: Content
    init(tint: Color = Routes05Tokens.blue, index: String? = nil, @ViewBuilder content: () -> Content) { self.tint = tint; self.index = index; self.content = content() }
    var body: some View {
        HStack(spacing: 11) {
            if let index { Text(index).font(.system(size: 22, weight: .bold, design: .monospaced)).frame(width: 48, alignment: .leading) }
            Rectangle().fill(tint).frame(width: 5)
            content
            Image(systemName: "chevron.right").font(.headline.weight(.black))
        }
        .padding(.horizontal, 5).frame(minHeight: 62)
        .foregroundStyle(Routes05Tokens.ink).background(Routes05Tokens.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }
    }
}

struct Routes05Rail<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(.leading, 18).overlay(alignment: .leading) { Rectangle().fill(Routes05Tokens.blue).frame(width: 4) }
            .padding(.horizontal, 16)
    }
}

struct Routes05SectionHeader: View {
    let title: String
    let action: String?
    let actionHandler: (() -> Void)?

    init(_ title: String, action: String? = nil, actionHandler: (() -> Void)? = nil) {
        self.title = title
        self.action = action
        self.actionHandler = actionHandler
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.black))
                .tracking(-0.5)
            Spacer(minLength: 8)
            if let action {
                Button(action: actionHandler ?? {}) {
                    Text(action)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Routes05Tokens.blue)
                }
                .frame(minHeight: 44)
            }
        }
        .foregroundStyle(Routes05Tokens.ink)
    }
}

/// Compact chrome used by contextual ROUTES screens. The native navigation bar
/// still owns back-swipe and dismissal; this view supplies the editorial route
/// language below it without introducing another navigation stack or dock.
struct Routes05ContextHeader: View {
    let section: String
    let eyebrow: String
    let title: String
    let detail: String?
    let accent: Color

    init(section: String, eyebrow: String, title: String, detail: String? = nil, accent: Color = Routes05Tokens.yellow) {
        self.section = section
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.accent = accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Routes05Mast(section: section)
            Routes05Chapter(eyebrow, title: title, detail: detail, accent: accent)
        }
        .accessibilityElement(children: .contain)
    }
}

struct Routes05SourcePanel<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color = Routes05Tokens.blue, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Routes05Tokens.surface)
            .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 5) }
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
    }
}

struct Routes05RouteRow<Content: View>: View {
    let index: String
    let tint: Color
    let content: Content
    let action: (() -> Void)?

    init(index: String, tint: Color, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.index = index
        self.tint = tint
        self.action = action
        self.content = content()
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var row: some View {
        HStack(spacing: 10) {
            Text(index).font(.system(.title3, design: .rounded).weight(.black))
                .frame(width: 34, alignment: .leading)
            Rectangle().fill(tint).frame(width: 4)
            content
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right").font(.caption.weight(.black))
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 62)
        .foregroundStyle(Routes05Tokens.ink)
        .background(Routes05Tokens.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }
    }
}

struct Routes05FilledTile: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).font(.headline.weight(.bold))
                    Spacer()
                    Text("↗").font(.caption.weight(.black))
                }
                Spacer(minLength: 3)
                Text(title).font(.headline.weight(.black)).lineLimit(2)
                Text(detail).font(.caption.weight(.medium)).lineLimit(2)
            }
            .foregroundStyle(Routes05Tokens.accentInk)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct Routes05IndexedRow<Content: View>: View {
    let index: String
    let tint: Color
    let indexWidth: CGFloat
    let content: Content

    init(index: String, tint: Color, indexWidth: CGFloat = 48, @ViewBuilder content: () -> Content) {
        self.index = index
        self.tint = tint
        self.indexWidth = indexWidth
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(index)
                .font(.system(.title2, design: .rounded).weight(.black))
                .frame(width: indexWidth, alignment: .leading)
            Rectangle().fill(tint).frame(width: 4)
            content
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.black))
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 62)
        .foregroundStyle(Routes05Tokens.ink)
        .background(Routes05Tokens.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }
    }
}

struct Routes05StateRow: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(tint).frame(width: 4)
            Image(systemName: "info.circle").foregroundStyle(tint)
            Text(text).font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 62, alignment: .leading)
        .background(Routes05Tokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Shared treatment for contextual ROUTES screens. It deliberately changes
/// presentation only; Lists, stores, navigation destinations and actions keep
/// their existing behavior.
struct Routes05ContextSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Routes05Tokens.canvas)
            .tint(Routes05Tokens.blue)
            .listStyle(.plain)
            .toolbarBackground(Routes05Tokens.canvas, for: .navigationBar)
    }
}

extension View {
    func routes05ContextSurface() -> some View {
        modifier(Routes05ContextSurface())
    }
}

#if DEBUG
enum Routes05DebugCapture {
    static let scrollToBottom = ProcessInfo.processInfo.arguments.contains("--routes05-bottom")
    static let scrollHorizontal = ProcessInfo.processInfo.arguments.contains("--routes05-scroll-horizontal")
}
#else
enum Routes05DebugCapture {
    static let scrollToBottom = false
    static let scrollHorizontal = false
}
#endif

enum Routes05DisplayFormat {
    static func compactTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
