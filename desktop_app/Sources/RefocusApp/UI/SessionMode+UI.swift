import SwiftUI

extension SessionMode {
    var color: Color {
        switch self {
        case .idle:
            return .gray
        case .work:
            return .green
        case .violationGrace:
            return .orange
        case .violationEnforced:
            return .red
        }
    }
}
