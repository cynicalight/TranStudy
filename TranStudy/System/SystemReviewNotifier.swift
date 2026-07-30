@preconcurrency import UserNotifications

enum ReviewNotificationError: Error {
  case permissionDenied
}

@MainActor
protocol ReviewNotificationCenterClient: AnyObject {
  func setDelegate(_ delegate: UNUserNotificationCenterDelegate)
  func authorizationStatus() async -> PreparationAuthorizationStatus
  func requestAuthorization() async throws -> Bool
  func removePendingNotificationRequests(withIdentifiers identifiers: [String])
  func add(_ request: UNNotificationRequest) async throws
}

@MainActor
private final class UserNotificationCenterClient: ReviewNotificationCenterClient {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
    center.delegate = delegate
  }

  func authorizationStatus() async -> PreparationAuthorizationStatus {
    switch await center.notificationSettings().authorizationStatus {
    case .notDetermined:
      .notDetermined
    case .authorized, .provisional, .ephemeral:
      .authorized
    case .denied:
      .denied
    @unknown default:
      .denied
    }
  }

  func requestAuthorization() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func add(_ request: UNNotificationRequest) async throws {
    try await center.add(request)
  }
}

@MainActor
final class SystemReviewNotifier: NSObject, ReviewNotifying {
  nonisolated static let requestIdentifier = "daily-review-reminder"

  var onReviewRequested: (() -> Void)?

  private let center: any ReviewNotificationCenterClient
  private let preferencesStore: any LanguageAndSpeechPreferencesStoring

  init(
    center: any ReviewNotificationCenterClient = UserNotificationCenterClient(),
    preferencesStore: any LanguageAndSpeechPreferencesStoring =
      UserDefaultsLanguageAndSpeechPreferencesStore()
  ) {
    self.center = center
    self.preferencesStore = preferencesStore
    super.init()
  }

  func start() {
    center.setDelegate(self)
  }

  func authorizationStatus() async -> PreparationAuthorizationStatus {
    await center.authorizationStatus()
  }

  func requestAuthorization() async throws -> Bool {
    try await center.requestAuthorization()
  }

  func replaceScheduledReminder(with reminder: ReviewReminder?) async throws {
    guard let reminder else {
      center.removePendingNotificationRequests(
        withIdentifiers: [Self.requestIdentifier]
      )
      return
    }

    let isAuthorized: Bool
    switch await center.authorizationStatus() {
    case .notDetermined:
      isAuthorized = try await center.requestAuthorization()
    case .authorized:
      isAuthorized = true
    case .denied:
      isAuthorized = false
    @unknown default:
      isAuthorized = false
    }
    guard isAuthorized else {
      throw ReviewNotificationError.permissionDenied
    }

    let content = UNMutableNotificationContent()
    let language = preferencesStore.load().interfaceLanguage
    content.title = AppLocalization.string("该复习了", language: language)
    content.body = AppLocalization.format(
      "今天有 %@ 张卡片待复习。",
      language: language,
      "\(reminder.dueCount)"
    )
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, reminder.date.timeIntervalSinceNow),
      repeats: false
    )
    let request = UNNotificationRequest(
      identifier: Self.requestIdentifier,
      content: content,
      trigger: trigger
    )
    try await center.add(request)
  }

  func handleResponse(identifier: String) {
    guard identifier == Self.requestIdentifier else {
      return
    }
    onReviewRequested?()
  }
}

extension SystemReviewNotifier: UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    await MainActor.run {
      handleResponse(identifier: response.notification.request.identifier)
    }
  }
}
