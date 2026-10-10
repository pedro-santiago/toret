import SwiftUI

// MARK: - Water-state glyph

/// The state of the water as a shape, so it does not rest on colour alone.
///
/// A drop, full for running, half for weak, struck through for dry, dashed for
/// unknown — readable in greyscale and to anyone who cannot tell the green from
/// the terracotta.
struct StateGlyph: View {
    let state: WaterState
    var size: CGFloat = 18
    var night = false

    var body: some View {
        let tint = state.color(night: night)
        ZStack {
            switch state {
            case .running:
                Icon.Drop().fill(tint)
            case .weak:
                Icon.Drop().stroke(tint, style: stroke)
                Icon.Drop().fill(tint)
                    .mask(alignment: .bottom) { Rectangle().frame(height: size * 0.5) }
            case .dry:
                Icon.Drop().stroke(tint, style: stroke)
                Path { path in
                    path.move(to: CGPoint(x: size * 0.1, y: size * 0.9))
                    path.addLine(to: CGPoint(x: size * 0.9, y: size * 0.1))
                }
                .stroke(tint, style: stroke)
            case .unknown:
                Icon.Drop().stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 2.5]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round) }
}

// MARK: - Rating

/// Five lozenges, filled in proportion to a rating. Stars would be a different
/// app's mark; the lozenge is this one's.
struct LozengeRating: View {
    var value: Double
    var size: CGFloat = 14
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0 ..< 5, id: \.self) { index in
                let fill = min(1, max(0, value - Double(index)))
                ZStack {
                    Icon.Lozenge().stroke(
                        Palette.ink.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)
                    )
                    Icon.Lozenge().fill(Palette.brass)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: size * fill)
                        }
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Nota \(value.formatted(.number.precision(.fractionLength(1)))) de 5"))
    }
}

/// The same five lozenges, tappable: the control the review sheet rates with.
struct LozengeRatingInput: View {
    @Binding var rating: Int
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1 ... 5, id: \.self) { value in
                Button {
                    // Tapping the current rating clears it: rating is optional.
                    rating = rating == value ? 0 : value
                } label: {
                    Icon.Lozenge()
                        .fill(value <= rating ? Palette.brass : Color.clear)
                        .overlay {
                            Icon.Lozenge().stroke(
                                value <= rating ? Palette.brass : Palette.ink.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
                            )
                        }
                        .frame(width: size, height: size)
                        .scaleEffect(value <= rating ? 1 : 0.92)
                        .animation(.spring(duration: 0.25, bounce: 0.3), value: rating)
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

/// A short label in a pill. `isOn` fills it; used both to display a fountain's
/// tags and to pick them.
struct TagChip: View {
    let label: String
    var isOn = false

    var body: some View {
        Text(label)
            .font(Typo.ui(12.5, 500))
            .foregroundStyle(isOn ? Palette.paperRaised : Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                Capsule().fill(isOn ? Palette.ink : Color.clear)
                Capsule().strokeBorder(Palette.ink.opacity(isOn ? 0 : 0.25), lineWidth: 1.2)
            }
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
            path.addRoundedRect(in: body, cornerSize: CGSize(width: 4, height: 4))
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
        date.formatted(
            .relative(presentation: .numeric, unitsStyle: .abbreviated)
                .locale(Locale(identifier: "pt_BR"))
        )
    }
}

extension ReportTag {
    var localizedLabel: String { label }
}
