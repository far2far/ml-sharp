import SwiftUI

/// Bottom status bar showing current pipeline stage and a cancel button.
struct StatusBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack {
            statusIndicator
            Text(state.status.label)
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if state.status.isRunning {
                Button("Cancel") {
                    state.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch state.status {
        case .idle:
            Circle()
                .fill(.secondary)
                .frame(width: 8, height: 8)
        case .running, .parsingPLY:
            ProgressView()
                .controlSize(.small)
        case .done:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case .failed:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        case .cancelled:
            Circle()
                .fill(.orange)
                .frame(width: 8, height: 8)
        }
    }
}
