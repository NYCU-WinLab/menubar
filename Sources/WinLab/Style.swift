import SwiftUI

/// Layout numbers, on the 4 pt grid the HIG uses. Modules sit inside the
/// window with concentric corners: module radius = window radius − inset.
enum Metrics {
    static let windowWidth: CGFloat = 340
    static let inset: CGFloat = 10
    static let windowRadius: CGFloat = 24
    static let moduleRadius: CGFloat = windowRadius - inset
    static let modulePadding: CGFloat = 12
    static let moduleSpacing: CGFloat = 8
    static let artworkRadius: CGFloat = moduleRadius - 6
}

extension View {
    /// Liquid Glass for controls only (HIG: never on the content layer);
    /// bordered styles before macOS 26.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// A round icon button, like the ones in Control Center.
    func circleButton(prominent: Bool = false) -> some View {
        glassButton(prominent: prominent)
            .buttonBorderShape(.circle)
    }

    /// A transient message floating over the content.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: .capsule)
        }
    }
}

/// A group of related content, on a standard fill (the content layer).
struct Module<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .frame(width: 14)
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                accessory
            }
            .foregroundStyle(.secondary)
            content
        }
        .padding(Metrics.modulePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.moduleRadius, style: .continuous))
    }
}

extension Module where Accessory == EmptyView {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        accessory = EmptyView()
        self.content = content()
    }
}

/// A quiet notice inside a module: why something is missing.
struct Notice: View {
    let text: String
    var symbol: String?

    var body: some View {
        Group {
            if let symbol { Label(text, systemImage: symbol) } else { Text(text) }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// A thin playback bar, like Control Center's Now Playing.
struct ProgressCapsule: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.secondary)
                Capsule().fill(.secondary)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}
