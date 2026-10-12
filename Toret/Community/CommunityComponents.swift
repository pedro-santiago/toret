import SwiftUI

// MARK: - Rating

/// Five diamonds, filled in proportion to a rating. Stars would be a different
/// app's mark; the diamond is this one's, and it prints in one ink so a rating
/// never competes with the water state's three.
struct DiamondRating: View {
    var value: Double
    var size: CGFloat = 16
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0 ..< 5, id: \.self) { index in
                let fill = min(1, max(0, value - Double(index)))
                ZStack {
                    Diamond().fill(Palette.inchiostro)
                        .mask(alignment: .leading) { Rectangle().frame(width: size * fill) }
                    Diamond().stroke(Palette.inchiostro, lineWidth: 1.5)
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Nota \(value.formatted(.number.precision(.fractionLength(1)))) de 5"))
    }
}

/// The same five diamonds, tappable: what the review sheet rates with.
struct DiamondRatingInput: View {
    @Binding var rating: Int
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1 ... 5, id: \.self) { value in
                Button {
                    // Tapping the current rating clears it: rating is optional.
                    rating = rating == value ? 0 : value
                } label: {
                    Diamond()
                        .fill(value <= rating ? Palette.inchiostro : Color.clear)
                        .overlay { Diamond().stroke(Palette.inchiostro, lineWidth: 2.5) }
                        .frame(width: size, height: size)
                        .scaleEffect(value <= rating ? 1 : 0.9)
                        .animation(Motion.ui, value: rating)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Sua nota"))
        .accessibilityValue(rating == 0 ? String(localized: "Sem nota") : String(localized: "\(rating) de 5"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: - Tags

/// A short label in a square frame. `isOn` fills it; used both to show a
/// fountain's tags and to pick them.
struct TagChip: View {
    let label: String
    var isOn = false

    var body: some View {
        Text(label)
            .font(Typo.ui(14, 600))
            .foregroundStyle(isOn ? Palette.carta : Palette.inchiostro)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isOn ? Palette.inchiostro : Color.clear)
            .overlay { Rectangle().strokeBorder(Palette.inchiostro, lineWidth: 2) }
    }
}

/// Lays its children out in rows, wrapping — for chips, whose number and width
/// are not known until the language is.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Tab glyph

extension Icon {
    /// A speech bubble with two lines of text — the community tab.
    struct Voices: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.74)
            path.addRect(body)
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: body.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: body.maxY))
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: body.height * 0.36))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.24, y: body.height * 0.36))
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: body.height * 0.64))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.6, y: body.height * 0.64))
            return path
        }
    }
}

// MARK: - Dates

extension Report {
    /// "há 2 h", "há 3 dias".
    var ago: String {
        Self.ago(date)
    }

    /// A report made a moment ago is stamped by this device's clock, a hair later
    /// than the clock that draws the row (or ahead of it, on a fast phone): it
    /// would read "em 0 seg.", which is never what happened. Nothing is "in the
    /// future" here, so the newest it can be is one second ago.
    static func ago(_ date: Date, now: Date = .now, locale: Locale = .autoupdatingCurrent) -> String {
        Formatting.relative(min(date, now.addingTimeInterval(-1)), to: now, locale: locale)
    }
}

extension ReportTag {
    var localizedLabel: String { label }
}
