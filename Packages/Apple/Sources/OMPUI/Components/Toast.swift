import SwiftUI

/// How long a toast stays visible (design-system.md section 2).
public enum ToastTiming {
    public static let visibleDuration: Duration = .seconds(4)
}

/// A short confirmation shown at the bottom ("Plan approved", inbox merge C-111).
///
/// It is announced to VoiceOver, hides itself after 4 seconds, and fades instead of sliding
/// when Reduce Motion is on (AC-15.4).
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(OMPFont.reason)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, OMPSpacing.medium)
                        .padding(.vertical, OMPSpacing.small + 4)
                        .ompCardBackground()
                        .padding(OMPSpacing.medium)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("toast")
                        .task(id: message) {
                            AccessibilityNotification.Announcement(message).post()
                            try? await Task.sleep(for: ToastTiming.visibleDuration)
                            guard !Task.isCancelled else { return }
                            self.message = nil
                        }
                }
            }
            .animation(reduceMotion ? nil : .default, value: message)
    }
}

extension View {
    /// Shows `message` as a toast while it is non-nil; sets it back to nil after 4 seconds.
    public func ompToast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
