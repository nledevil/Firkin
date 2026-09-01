import SwiftUI

/// Sheet showing live output while a brew action runs.
struct OperationConsoleView: View {
    @Environment(PackageStore.self) private var store

    var body: some View {
        if let operation = store.activeOperation {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    statusIcon(for: operation)
                    Text(operation.title)
                        .font(.headline)
                    Spacer()
                }
                .padding()
                Divider()
                ScrollView {
                    Text(operation.log.isEmpty ? "Waiting for output…" : operation.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .defaultScrollAnchor(.bottom)
                Divider()
                HStack {
                    if let failure = operation.failureMessage {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Done") {
                        store.activeOperation = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(operation.isRunning)
                }
                .padding()
            }
            .frame(width: 580, height: 380)
            .interactiveDismissDisabled(operation.isRunning)
        }
    }

    @ViewBuilder
    private func statusIcon(for operation: PackageStore.Operation) -> some View {
        if operation.isRunning {
            ProgressView()
                .controlSize(.small)
        } else if operation.failureMessage != nil {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
