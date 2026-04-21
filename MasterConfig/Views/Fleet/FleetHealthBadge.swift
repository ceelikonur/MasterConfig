import SwiftUI

// MARK: - Size

enum FleetHealthBadgeSize {
    case small
    case large

    var diameter: CGFloat {
        switch self {
        case .small: return 24
        case .large: return 56
        }
    }

    var iconFont: Font {
        switch self {
        case .small: return .system(size: 12, weight: .bold)
        case .large: return .system(size: 26, weight: .bold)
        }
    }

    var scoreFont: Font {
        switch self {
        case .small: return .caption2.bold()
        case .large: return .title3.bold()
        }
    }
}

// MARK: - Badge

struct FleetHealthBadge: View {
    let status: FleetHealthStatus?
    let score: Int?
    let size: FleetHealthBadgeSize

    init(status: FleetHealthStatus?, score: Int? = nil, size: FleetHealthBadgeSize = .small) {
        self.status = status
        self.score = score
        self.size = size
    }

    var body: some View {
        HStack(spacing: size == .large ? 12 : 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: size.diameter, height: size.diameter)
                Circle()
                    .strokeBorder(color.opacity(0.45), lineWidth: 1)
                    .frame(width: size.diameter, height: size.diameter)
                Image(systemName: iconName)
                    .font(size.iconFont)
                    .foregroundStyle(color)
            }

            if let score {
                Text("\(score)")
                    .font(size.scoreFont)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        (status ?? .unknown).icon
    }

    private var color: Color {
        switch status {
        case .healthy:              return .green
        case .warning:              return .yellow
        case .critical:             return .red
        case .unknown, .none:       return .gray
        }
    }
}

// MARK: - Helper

func fleetColor(for status: FleetHealthStatus?) -> Color {
    switch status {
    case .healthy:        return .green
    case .warning:        return .yellow
    case .critical:       return .red
    case .unknown, .none: return .gray
    }
}

func fleetColor(forSeverity severity: FleetIssueSeverity) -> Color {
    switch severity {
    case .info:     return .blue
    case .warning:  return .yellow
    case .critical: return .red
    }
}
