import SwiftUI

private enum PreparationStep: Int, CaseIterable {
  case accessibility
  case translationService
  case notifications
  case ready

  var title: String {
    switch self {
    case .accessibility:
      "划词权限"
    case .translationService:
      "翻译服务"
    case .notifications:
      "复习提醒"
    case .ready:
      "准备完成"
    }
  }

  var systemImage: String {
    switch self {
    case .accessibility:
      "hand.point.up.left.fill"
    case .translationService:
      "network"
    case .notifications:
      "bell.badge.fill"
    case .ready:
      "checkmark.seal.fill"
    }
  }
}

struct InitialPreparationView: View {
  let shell: ApplicationShell
  @State private var step: PreparationStep = .accessibility

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      stepContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)

      Divider()

      controls
        .padding(20)
    }
    .frame(width: 620, height: 520)
    .task {
      await shell.refreshPreparationStatus()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("设置 TranStudy", systemImage: "character.book.closed.fill")
          .font(.title2.weight(.semibold))
        Spacer()
        Text("\(step.rawValue + 1) / \(PreparationStep.allCases.count)")
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      ProgressView(
        value: Double(step.rawValue + 1),
        total: Double(PreparationStep.allCases.count)
      )
    }
    .padding(24)
  }

  @ViewBuilder
  private var stepContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      Image(systemName: step.systemImage)
        .font(.system(size: 38))
        .foregroundStyle(TranStudyDesign.accentColor)

      Text(step.title)
        .font(.title.bold())

      switch step {
      case .accessibility:
        accessibilityStep
      case .translationService:
        translationServiceStep
      case .notifications:
        notificationsStep
      case .ready:
        readyStep
      }
    }
    .frame(maxWidth: 500, alignment: .leading)
  }

  private var accessibilityStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("辅助功能权限让 TranStudy 在你完成鼠标划词后显示翻译图标。只有点击图标后，应用才会读取上下文并请求翻译。")
        .foregroundStyle(.secondary)

      capabilityStatus(
        shell.accessibilityAuthorizationStatus,
        availableText: "已允许读取明确触发的文字选区",
        unavailableText: "尚未允许；仍可使用 \(shell.translationShortcut.title) 翻译剪贴板"
      )

      HStack {
        Button("请求辅助功能权限") {
          shell.requestAccessibilityAuthorization()
        }
        .buttonStyle(.borderedProminent)

        Button("重新检查") {
          Task {
            await shell.refreshPreparationStatus()
          }
        }
      }
    }
  }

  private var translationServiceStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("选择翻译服务并测试连接。TranStudy 只会使用当前选择的供应商，不会在失败时把文本转发给其他服务。")
        .foregroundStyle(.secondary)

      TranslationServiceSetupView(shell: shell)
    }
  }

  private var notificationsStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("通知只在存在到期卡片时提醒你。拒绝或暂时跳过不会影响翻译、学习记录和复习计算。")
        .foregroundStyle(.secondary)

      capabilityStatus(
        shell.notificationAuthorizationStatus,
        availableText: "已允许复习提醒",
        unavailableText: "尚未允许；可以稍后在系统设置中开启"
      )

      Button("请求通知权限") {
        Task {
          await shell.requestNotificationAuthorization()
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(shell.notificationAuthorizationStatus == .authorized)
    }
  }

  private var readyStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("你现在可以进入主界面。未完成的项目会保留为轻量提示，不会反复强制弹出引导。")
        .foregroundStyle(.secondary)

      Toggle(
        "登录时启动 TranStudy",
        isOn: Binding(
          get: { shell.isLaunchAtLoginEnabled },
          set: { shell.setLaunchAtLoginEnabled($0) }
        )
      )

      Text("开启后，TranStudy 会在登录时进入菜单栏，以便继续提供划词和到期提醒。此选项默认关闭。")
        .font(.caption)
        .foregroundStyle(.secondary)

      ForEach(PreparationCapability.allCasesForDisplay) { capability in
        preparationSummaryRow(capability)
      }
    }
  }

  private var controls: some View {
    HStack {
      if step != .accessibility {
        Button("上一步") {
          move(by: -1)
        }
      }

      Spacer()

      Button("稍后处理") {
        shell.completeInitialPreparation()
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      if step == .ready {
        Button("进入 TranStudy") {
          shell.completeInitialPreparation()
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button("继续") {
          move(by: 1)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private func move(by offset: Int) {
    guard let next = PreparationStep(rawValue: step.rawValue + offset) else {
      return
    }
    step = next
  }

  private func capabilityStatus(
    _ status: PreparationAuthorizationStatus,
    availableText: String,
    unavailableText: String
  ) -> some View {
    let isAuthorized = status == .authorized
    return Label(
      isAuthorized ? availableText : unavailableText,
      systemImage: isAuthorized ? "checkmark.circle.fill" : "info.circle.fill"
    )
    .foregroundStyle(isAuthorized ? .green : .secondary)
  }

  private func preparationSummaryRow(_ capability: PreparationCapability) -> some View {
    let isAvailable = !shell.missingPreparationCapabilities.contains(capability)
    return Label(
      capability.title,
      systemImage: isAvailable ? "checkmark.circle.fill" : "circle.dashed"
    )
    .foregroundStyle(isAvailable ? .green : .secondary)
  }
}

struct PreparationStatusBanner: View {
  let shell: ApplicationShell

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(TranStudyDesign.accentColor)

      VStack(alignment: .leading, spacing: 2) {
        Text("还有功能尚未准备")
          .font(.callout.weight(.semibold))
        Text(shell.missingPreparationCapabilities.map(\.title).joined(separator: "、"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button("检查与修复") {
        shell.presentPreparation()
      }
      .buttonStyle(.bordered)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
  }
}

extension PreparationCapability {
  fileprivate static let allCasesForDisplay: [PreparationCapability] = [
    .accessibility,
    .translationService,
    .notifications,
  ]

  fileprivate var title: String {
    switch self {
    case .accessibility:
      "鼠标划词"
    case .translationService:
      "翻译服务"
    case .notifications:
      "复习通知"
    }
  }
}
