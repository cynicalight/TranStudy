import SwiftUI

struct TodayReviewView: View {
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  @State private var hasCompletedReviewFlip = false

  let shell: ApplicationShell

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        PageHeader(
          title: "今日复习",
          subtitle: "把今天该记住的内容，变成一个轻松完成的小目标。",
          systemImage: "rectangle.stack.fill"
        )

        HStack(spacing: 14) {
          SummaryCard(
            title: "待复习",
            value: shell.learningSummary.dueCount,
            systemImage: "clock",
            tint: .orange
          )
          SummaryCard(
            title: "单词",
            value: shell.learningSummary.wordCount,
            systemImage: "textformat.abc",
            tint: .blue
          )
          SummaryCard(
            title: "句子",
            value: shell.learningSummary.sentenceCount,
            systemImage: "text.quote",
            tint: .purple
          )
        }

        if let item = shell.currentReviewItem {
          reviewSession(item)
        } else {
          reviewStatus
        }
      }
      .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .navigationTitle("今日复习")
  }

  private func reviewSession(_ item: LearningItem) -> some View {
    VStack(spacing: 16) {
      ReviewFlipCard(
        isFlipped: shell.isReviewAnswerVisible,
        isBackFaceInteractive: hasCompletedReviewFlip,
        onFlip: shell.revealCurrentReviewAnswer
      ) {
        Text(item.canonicalForm)
          .font(.system(size: 48, weight: .semibold, design: .rounded))
          .minimumScaleFactor(0.65)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } back: {
        reviewAnswer(item)
      }
      .task(id: shell.isReviewAnswerVisible) {
        hasCompletedReviewFlip = false
        guard shell.isReviewAnswerVisible else {
          return
        }

        let duration =
          accessibilityReduceMotion
          ? ReviewFlipMotion.reducedMotionCompletionDelay
          : ReviewFlipMotion.completionDelay
        try? await Task.sleep(for: duration)
        guard !Task.isCancelled, shell.isReviewAnswerVisible else {
          return
        }
        hasCompletedReviewFlip = true
      }

      Group {
        if !showsNextReviewButton {
          HStack(spacing: 10) {
            ForEach(ReviewRating.allCases, id: \.self) { rating in
              Button {
                Task {
                  await shell.rateCurrentReview(rating)
                }
              } label: {
                Text(rating.title)
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
              .tint(rating.tint)
              .disabled(shell.isReviewRating || shell.selectedReviewRating != nil)
            }
          }
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
          Button {
            shell.advanceToNextReview()
          } label: {
            Label("下一个", systemImage: "arrow.right")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
      }
      .animation(
        .easeOut(duration: accessibilityReduceMotion ? 0.12 : 0.16),
        value: showsNextReviewButton
      )
    }
  }

  private var showsNextReviewButton: Bool {
    shell.selectedReviewRating != nil && hasCompletedReviewFlip
  }

  private func reviewAnswer(_ item: LearningItem) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(item.canonicalForm)
          .font(.largeTitle.weight(.semibold))
        if !item.pronunciation.isEmpty {
          Text(item.pronunciation)
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !item.partOfSpeech.isEmpty {
          Text(item.partOfSpeech)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
        }
      }

      Text(item.contextualMeaning)
        .font(.title3.weight(.medium))

      VStack(alignment: .leading, spacing: 7) {
        Text(item.exampleSentence)
          .font(.body)
          .italic()
        Text(item.sentenceTranslation)
          .foregroundStyle(.secondary)
      }

      let otherEncounters = Array(item.encounters.dropFirst())
      if !otherEncounters.isEmpty {
        DisclosureGroup("其他义项与例句（\(otherEncounters.count)）") {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(otherEncounters) { encounter in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(encounter.contextualMeaning)
                    .fontWeight(.medium)
                  if !encounter.partOfSpeech.isEmpty {
                    Text(encounter.partOfSpeech)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
                Text(encounter.exampleSentence)
                  .italic()
                Text(encounter.sentenceTranslation)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .padding(.top, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var reviewStatus: some View {
    HStack(alignment: .top, spacing: 18) {
      Image(systemName: reviewStatusImage)
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(reviewStatusTint)
        .frame(width: 52, height: 52)
        .background(reviewStatusTint.opacity(0.1), in: .circle)

      VStack(alignment: .leading, spacing: 7) {
        Text(reviewStatusTitle)
          .font(.title3.weight(.semibold))
        Text(reviewStatusDescription)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Divider()
          .padding(.vertical, 5)

        Label {
          Text("在任意应用复制单词或短语，然后按下 ")
            + Text("F5").fontWeight(.semibold)
            + Text(" 开始积累。")
        } icon: {
          Image(systemName: "character.bubble")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding(22)
    .contentSurface()
  }

  private var reviewStatusTitle: String {
    if shell.learningSummary.dueCount == 0 {
      return "今天没有待复习"
    }
    return "还有 \(shell.learningSummary.dueCount) 项等待复习"
  }

  private var reviewStatusDescription: String {
    if shell.learningSummary.dueCount == 0 {
      return "当前没有到期内容。继续从真实语境中积累，复习会在合适的时间出现。"
    }
    return "完成今天的复习，保持记忆节奏稳定。"
  }

  private var reviewStatusImage: String {
    shell.learningSummary.dueCount == 0 ? "checkmark" : "clock.arrow.circlepath"
  }

  private var reviewStatusTint: Color {
    shell.learningSummary.dueCount == 0 ? .green : .orange
  }
}

private struct ReviewFlipCard<Front: View, Back: View>: View {
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

  let isFlipped: Bool
  let isBackFaceInteractive: Bool
  let onFlip: () -> Void
  let front: Front
  let back: Back

  init(
    isFlipped: Bool,
    isBackFaceInteractive: Bool,
    onFlip: @escaping () -> Void,
    @ViewBuilder front: () -> Front,
    @ViewBuilder back: () -> Back
  ) {
    self.isFlipped = isFlipped
    self.isBackFaceInteractive = isBackFaceInteractive
    self.onFlip = onFlip
    self.front = front()
    self.back = back()
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      if accessibilityReduceMotion {
        frontFace
          .opacity(isFlipped ? 0 : 1)
        backFace
          .opacity(isFlipped ? 1 : 0)
      } else {
        frontFace
          .modifier(
            ReviewCardFaceEffect(
              progress: isFlipped ? 1 : 0,
              isBack: false
            ))
        backFace
          .modifier(
            ReviewCardFaceEffect(
              progress: isFlipped ? 1 : 0,
              isBack: true
            ))
      }
    }
    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    .animation(isFlipped ? flipAnimation : nil, value: isFlipped)
  }

  private var frontFace: some View {
    Button(action: onFlip) {
      front
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 300)
        .contentSurface()
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(!isFlipped)
    .accessibilityHidden(isFlipped)
    .accessibilityHint("显示完整释义和例句")
  }

  private var backFace: some View {
    back
      .padding(28)
      .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
      .contentSurface()
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .allowsHitTesting(isBackFaceInteractive)
      .accessibilityHidden(!isBackFaceInteractive)
  }

  private var flipAnimation: Animation {
    ReviewFlipMotion.animation(reduceMotion: accessibilityReduceMotion)
  }
}

private enum ReviewFlipMotion {
  static let completionDelay = Duration.milliseconds(440)
  static let reducedMotionCompletionDelay = Duration.milliseconds(120)

  static func animation(reduceMotion: Bool) -> Animation {
    if reduceMotion {
      return .easeOut(duration: 0.12)
    }
    return .spring(duration: 0.44, bounce: 0.14)
  }
}

private struct ReviewCardFaceEffect: @MainActor AnimatableModifier {
  var progress: Double
  let isBack: Bool

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let rotation = progress * 180 + (isBack ? 180 : 0)
    let isVisible = isBack ? progress >= 0.5 : progress < 0.5
    let midpointScale = 1 - sin(progress * .pi) * 0.015

    content
      .opacity(isVisible ? 1 : 0)
      .scaleEffect(midpointScale)
      .rotation3DEffect(
        .degrees(rotation),
        axis: (x: 0, y: 1, z: 0),
        anchor: .center,
        perspective: 0.7
      )
  }
}

extension ReviewRating {
  fileprivate var title: String {
    switch self {
    case .forgot:
      "忘记"
    case .hard:
      "困难"
    case .remembered:
      "记得"
    case .easy:
      "简单"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .forgot:
      .red
    case .hard:
      .orange
    case .remembered:
      .blue
    case .easy:
      .green
    }
  }
}

private struct SummaryCard: View {
  let title: String
  let value: Int
  let systemImage: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
        Spacer()
        Text(title)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Text(value, format: .number)
        .font(.system(size: 30, weight: .semibold, design: .rounded))
        .contentTransition(.numericText())
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentSurface()
    .accessibilityElement(children: .combine)
  }
}

#if DEBUG
  #Preview("今日复习") {
    PreviewFactory.todayReviewView()
  }

  #Preview("统计卡片") {
    SummaryCard(
      title: "待复习",
      value: 4,
      systemImage: "clock",
      tint: .orange
    )
    .padding()
    .frame(width: 260)
  }
#endif
