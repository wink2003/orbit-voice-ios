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

    static func foreground(on accent: Color) -> Color { ink }
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
                    .frame(width: 36, height: 36)
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
                Text("↗").font(.system(size: 27, weight: .black)).foregroundStyle(Routes05Tokens.ink)
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
