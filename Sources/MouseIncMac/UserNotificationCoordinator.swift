@preconcurrency import UserNotifications

@MainActor
final class UserNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func postOCRResult(text: String) {
        Task { [center] in
            let settings = await center.notificationSettings()
            let isAuthorized: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .notDetermined:
                isAuthorized = (try? await center.requestAuthorization(
                    options: [.alert, .sound]
                )) ?? false
            case .denied:
                isAuthorized = false
            @unknown default:
                isAuthorized = false
            }
            guard isAuthorized else {
                DiagnosticLogger.shared.log("OCR notification unavailable; authorization denied")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = text.isEmpty ? "OCR 未识别到文字" : "OCR 识别完成，已复制"
            content.body = text.isEmpty ? "剪贴板内容未改变" : Self.previewText(text)
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "ocr-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
            } catch {
                DiagnosticLogger.shared.log("OCR notification delivery failed")
            }
        }
    }

    static func previewText(_ text: String, limit: Int = 120) -> String {
        let normalized = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(1, limit))) + "…"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
