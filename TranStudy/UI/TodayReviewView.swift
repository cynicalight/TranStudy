import Foundation
import SwiftUI

struct TodayReviewView: View {
  let shell: ApplicationShell

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          PageHeader(
            title: "今日复习",
            subtitle: "把今天该记住的内容，变成一个轻松完成的小目标。",
            systemImage: "rectangle.stack.fill"
          )

          HStack(spacing: 14) {
            SummaryCard(
              title: "今日待复习",
              value: shell.learningSummary.dueCount,
              systemImage: "clock",
              tint: .orange
            )
            SummaryCard(
              title: "今日已复习",
              value: shell.learningSummary.reviewedTodayCount,
              systemImage: "checkmark.circle",
              tint: .green
            )
            SummaryCard(
              title: "连续学习天数",
              value: shell.learningSummary.streakDayCount,
              systemImage: "flame",
              tint: .pink
            )
          }

          HStack(spacing: 14) {
            SummaryCard(
              title: "学习中单词",
              value: shell.learningSummary.wordCount,
              systemImage: "textformat.abc",
              systemImageLocale: Locale(identifier: "en"),
              tint: .blue
            )
            SummaryCard(
              title: "学习中句子",
              value: shell.learningSummary.sentenceCount,
              systemImage: "text.quote",
              tint: .purple
            )
          }

          NavigationLink {
            ReviewSessionView(shell: shell)
              .onAppear {
                shell.startNextReviewBatch()
              }
          } label: {
            Label("开始复习", systemImage: "play.fill")
              .font(.title3.weight(.semibold))
              .foregroundStyle(isStartReviewDisabled ? .black : .white)
              .padding(.vertical, 10)
              .frame(maxWidth: .infinity, minHeight: 64)
              .contentShape(.capsule)
          }
          .adaptiveTintedGlassButton()
          .disabled(isStartReviewDisabled)
        }
        .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .top)
      }
    }
  }

  private var isStartReviewDisabled: Bool {
    shell.currentReviewItem == nil && !shell.hasMoreReviewBatches
  }
}

private struct ReviewSessionView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  @State private var hasCompletedReviewFlip = false
  @State private var spellingAttempt = ""
  @State private var submittedSpellingAttempt: String?
  @State private var isSpellingShaking = false
  @FocusState private var isSpellingAttemptFocused: Bool

  let shell: ApplicationShell

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        PageHeader(
          title: "卡片复习",
          subtitle: "先回忆答案，再根据记忆情况完成评分。",
          systemImage: "rectangle.stack.fill"
        )

        if shell.isImmediateSpellingReview, let item = shell.currentSpellingItem {
          spellingSession(item)
        } else if let item = shell.currentReviewItem {
          reviewSession(item)
        } else if let item = shell.currentSpellingItem {
          spellingSession(item)
        } else if shell.hasMoreReviewBatches {
          completedBatchStatus
        } else {
          reviewStatus
        }
      }
      .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .navigationTitle("卡片复习")
  }

  private var completedBatchStatus: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("本组复习完成", systemImage: "checkmark.circle.fill")
        .font(.title2.weight(.semibold))
        .foregroundStyle(.green)
      Text("还有 \(shell.remainingReviewCount) 张到期卡片。你可以继续下一组，或稍后再回来。")
        .foregroundStyle(.secondary)

      HStack {
        Button {
          shell.startNextReviewBatch()
        } label: {
          Label("继续下一组", systemImage: "arrow.right")
        }
        .buttonStyle(.borderedProminent)

        Button("稍后继续") {
          dismiss()
        }
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentSurface()
  }

  private func reviewSession(_ item: LearningItem) -> some View {
    VStack(spacing: 16) {
      ReviewFlipCard(
        isFlipped: shell.isReviewAnswerVisible,
        isBackFaceInteractive: hasCompletedReviewFlip,
        onFlip: shell.revealCurrentReviewAnswer,
        onSpeak: {
          if shell.selectedReviewRating != nil {
            shell.startCurrentReviewSpelling()
          } else {
            shell.speak(item.kind == .word ? item.canonicalForm : item.sourceText)
          }
        }
      ) {
        Text(item.kind == .sentence ? item.sourceText : item.canonicalForm)
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

      VStack(spacing: 12) {
        Button {
          Task {
            await shell.confirmCurrentReviewOrRemember()
          }
        } label: {
          EmptyView()
        }
        .keyboardShortcut(.return, modifiers: [])
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)

        HStack(spacing: 10) {
          ForEach(ReviewRating.allCases, id: \.self) { rating in
            Button {
              Task {
                await shell.rateCurrentReview(rating)
              }
            } label: {
              Text(LocalizedStringKey(rating.title))
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(rating.tint)
            .opacity(
              shell.selectedReviewRating == nil || shell.selectedReviewRating == rating ? 1 : 0.4
            )
            .overlay(alignment: .topTrailing) {
              if shell.selectedReviewRating == rating {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(rating.tint)
                  .font(.title3)
                  .padding(8)
              }
            }
            .disabled(shell.isReviewRating || shell.selectedReviewRating != nil)
            .keyboardShortcut(rating.shortcut, modifiers: [])
          }
        }

        if let rating = shell.selectedReviewRating {
          Label {
            Text(shell.localizedFormat("已选择：%@", shell.localized(rating.title)))
          } icon: {
            Image(systemName: "checkmark.circle.fill")
          }
          .font(.callout.weight(.semibold))
          .foregroundStyle(rating.tint)
          .transition(.opacity.combined(with: .scale(scale: 0.98)))

          Button("撤销选择") {
            shell.cancelCurrentReviewRating()
          }
          .buttonStyle(.borderless)
          .disabled(shell.isReviewRating)
          .keyboardShortcut(.escape, modifiers: [])
        }

        if showsNextReviewButton {
          Button {
            shell.startCurrentReviewSpelling()
          } label: {
            Label("开始拼写", systemImage: "text.cursor")
              .font(.title3.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 64)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(shell.isReviewRating)
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
      }
      .animation(
        .easeOut(duration: accessibilityReduceMotion ? 0.12 : 0.16),
        value: shell.selectedReviewRating
      )
    }
  }

  private func spellingSession(_ item: LearningItem) -> some View {
    let expectedCharacters = Array(item.canonicalForm)
    let expectedInputLength = SpellingAnswer.inputCharacters(in: item.canonicalForm).count
    let enteredCharacters = Array(submittedSpellingAttempt ?? spellingAttempt)

    return VStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 24) {
        Label("拼写复习", systemImage: "speaker.wave.2.fill")
          .font(.title3.weight(.semibold))

        Text("听发音，根据释义拼写英文单词。共 \(expectedInputLength) 个字母。")
          .foregroundStyle(.secondary)

        Text(item.contextualMeaning)
          .font(.system(size: 42, weight: .semibold, design: .rounded))
          .minimumScaleFactor(0.7)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, minHeight: 128)

        SpellingAnswerSlots(
          expectedCharacters: expectedCharacters,
          enteredCharacters: enteredCharacters,
          tint: spellingSlotTint
        )
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
          guard shell.spellingReviewResult != true else {
            return
          }
          isSpellingAttemptFocused = true
        }
        .offset(x: isSpellingShaking ? -7 : 0)
        .animation(
          accessibilityReduceMotion
            ? nil
            : .default.repeatCount(4, autoreverses: true),
          value: isSpellingShaking
        )

        if let spellingReviewResult = shell.spellingReviewResult {
          Label(
            spellingReviewResult
              ? "拼写正确"
              : "拼写错误，请先查看正确单词卡",
            systemImage: spellingReviewResult ? "checkmark.circle.fill" : "xmark.circle.fill"
          )
          .font(.callout.weight(.semibold))
          .foregroundStyle(spellingReviewResult ? .green : .red)
          .frame(maxWidth: .infinity)

          if !spellingReviewResult {
            VStack(alignment: .leading, spacing: 18) {
              Label("正确单词卡", systemImage: "rectangle.fill.on.rectangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

              reviewAnswer(item)

              Button {
                retrySpelling()
              } label: {
                Label("再次拼写", systemImage: "arrow.counterclockwise")
                  .font(.headline)
                  .frame(maxWidth: .infinity, minHeight: 48)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
            }
            .padding(22)
            .background(.orange.opacity(0.08), in: .rect(cornerRadius: 16))
            .overlay {
              RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.25), lineWidth: 1)
            }
          }
        }

        TextField("", text: $spellingAttempt)
          .textFieldStyle(.plain)
          .focused($isSpellingAttemptFocused)
          .frame(width: 1, height: 1)
          .opacity(0.01)
          .disabled(shell.spellingReviewResult == true)
          .onSubmit {
            handleSpellingReturn(expectedLength: expectedInputLength)
          }
          .onKeyPress(.space) {
            shell.speak(item.canonicalForm)
            return .handled
          }
          .onKeyPress(.return) {
            handleSpellingReturn(expectedLength: expectedInputLength)
            return .handled
          }
      }
      .padding(28)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentSurface()
      .task(id: item.id) {
        spellingAttempt = ""
        submittedSpellingAttempt = nil
        await Task.yield()
        isSpellingAttemptFocused = true
        shell.speak(item.canonicalForm)
      }
      .task(id: shell.spellingReviewResult) {
        guard let spellingReviewResult = shell.spellingReviewResult else {
          return
        }

        if !spellingReviewResult {
          if !accessibilityReduceMotion {
            isSpellingShaking = true
          }
          return
        }
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else {
          return
        }
        isSpellingShaking = false
        spellingAttempt = ""
        await shell.advanceToNextSpellingReview()
        isSpellingAttemptFocused = true
      }
      .onChange(of: spellingAttempt) { _, attempt in
        let limitedAttempt = String(attempt.prefix(expectedInputLength))
        if spellingAttempt != limitedAttempt {
          spellingAttempt = limitedAttempt
        }
      }
    }
  }

  private func handleSpellingReturn(expectedLength: Int) {
    if shell.spellingReviewResult == false {
      retrySpelling()
      return
    }

    submitSpelling(expectedLength: expectedLength)
  }

  private func submitSpelling(expectedLength: Int) {
    guard spellingAttempt.count == expectedLength else {
      return
    }
    let submittedAttempt = spellingAttempt
    submittedSpellingAttempt = submittedAttempt
    Task {
      await shell.submitCurrentSpelling(submittedAttempt)
    }
  }

  private func retrySpelling() {
    isSpellingShaking = false
    spellingAttempt = ""
    submittedSpellingAttempt = nil
    shell.retryCurrentSpelling()
    isSpellingAttemptFocused = true
  }

  private var spellingSlotTint: Color {
    switch shell.spellingReviewResult {
    case true:
      .green
    case false:
      .red
    case nil:
      .primary
    }
  }

  private var showsNextReviewButton: Bool {
    shell.selectedReviewRating != nil && hasCompletedReviewFlip
  }

  private func reviewAnswer(_ item: LearningItem) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      if item.kind == .sentence {
        Label("句子卡", systemImage: "text.quote")
          .font(.caption.weight(.medium))
          .foregroundStyle(.purple)
        HStack {
          Text(item.sourceText)
            .font(.title3.weight(.medium))
          SpeechButton(text: item.sourceText, speak: shell.speak)
        }
        Text(item.sentenceTranslation)
          .font(.title2.weight(.medium))
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(item.canonicalForm)
            .font(.largeTitle.weight(.semibold))
          SpeechButton(text: item.canonicalForm, speak: shell.speak)
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
          HStack {
            HighlightedExampleSentence(
              sentence: item.exampleSentence,
              vocabulary: item.canonicalForm
            )
              .font(.body)
              .italic()
            SpeechButton(text: item.exampleSentence, speak: shell.speak)
          }
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
                  HStack {
                    HighlightedExampleSentence(
                      sentence: encounter.exampleSentence,
                      vocabulary: item.canonicalForm
                    )
                      .italic()
                    SpeechButton(
                      text: encounter.exampleSentence,
                      speak: shell.speak
                    )
                  }
                  Text(encounter.sentenceTranslation)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .padding(.top, 8)
          }
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
            + Text(shell.translationShortcut.title).fontWeight(.semibold)
            + Text(" 开始积累。")
        } icon: {
          Image(systemName: "character.bubble")
        }
        .font(.callout)
        .foregroundStyle(.secondary)

        if shell.learningSummary.dueCount == 0 {
          Button("返回今日复习") {
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .padding(.top, 4)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(22)
    .contentSurface()
  }

  private var reviewStatusTitle: String {
    if shell.learningSummary.dueCount == 0 {
      return shell.localized("今天的复习已完成")
    }
    return shell.localizedFormat(
      "还有 %@ 项等待复习",
      "\(shell.learningSummary.dueCount)"
    )
  }

  private var reviewStatusDescription: String {
    if shell.learningSummary.dueCount == 0 {
      return shell.localized(
        "当前没有到期内容。继续从真实语境中积累，复习会在合适的时间出现。"
      )
    }
    return shell.localized("完成今天的复习，保持记忆节奏稳定。")
  }

  private var reviewStatusImage: String {
    shell.learningSummary.dueCount == 0 ? "checkmark" : "clock.arrow.circlepath"
  }

  private var reviewStatusTint: Color {
    shell.learningSummary.dueCount == 0 ? .green : .orange
  }
}

private struct HighlightedExampleSentence: View {
  let sentence: String
  let vocabulary: String

  var body: some View {
    Text(highlightedSentence)
  }

  private var highlightedSentence: AttributedString {
    var attributedSentence = AttributedString(sentence)
    let normalizedVocabulary = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedVocabulary.isEmpty else {
      return attributedSentence
    }

    for matchRange in ExampleSentenceVocabularyMatcher.matchingRanges(
      in: sentence,
      vocabulary: normalizedVocabulary
    ) {
      let matchNSRange = NSRange(matchRange, in: sentence)
      guard let range = Range(matchNSRange, in: attributedSentence) else {
        continue
      }
      attributedSentence[range].foregroundColor = .accentColor
      attributedSentence[range].font = .body.bold()
    }
    return attributedSentence
  }
}

private struct SpellingAnswerSlots: View {
  let expectedCharacters: [Character]
  let enteredCharacters: [Character]
  let tint: Color

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(expectedCharacters.enumerated()), id: \.offset) { index, expectedCharacter in
        if expectedCharacter.isWhitespace {
          Color.clear
            .frame(width: 16, height: 47)
        } else {
          let enteredIndex = SpellingAnswer.inputCharacters(
            in: String(expectedCharacters[..<index])
          ).count

          VStack(spacing: 3) {
            if enteredIndex < enteredCharacters.count {
              Text(String(enteredCharacters[enteredIndex]))
                .font(.system(.title, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
            } else {
              Text(" ")
                .font(.system(.title, design: .monospaced).weight(.semibold))
                .hidden()
            }
            Rectangle()
              .fill(tint)
              .frame(width: 28, height: 2)
          }
          .frame(width: 32, height: 47, alignment: .bottom)
        }
      }
    }
  }
}

private struct SpellingReviewPreview: View {
  @State private var attempt = "insp"
  @FocusState private var isAttemptFocused: Bool

  private let expectedCharacters = Array("in spite of")

  private var expectedInputLength: Int {
    SpellingAnswer.inputCharacters(in: String(expectedCharacters)).count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Label("拼写复习", systemImage: "speaker.wave.2.fill")
        .font(.title3.weight(.semibold))

      Text("听发音，根据释义拼写英文单词。共 \(expectedInputLength) 个字母。")
        .foregroundStyle(.secondary)

      Text("意外发现美好事物的幸运")
        .font(.system(size: 42, weight: .semibold, design: .rounded))
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 128)

      SpellingAnswerSlots(
        expectedCharacters: expectedCharacters,
        enteredCharacters: Array(attempt),
        tint: .primary
      )
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onTapGesture {
        isAttemptFocused = true
      }

      TextField("", text: $attempt)
        .textFieldStyle(.plain)
        .focused($isAttemptFocused)
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .onChange(of: attempt) { _, newValue in
          attempt = String(newValue.prefix(expectedInputLength))
        }
        .onKeyPress(.space) {
          .handled
        }
        .onKeyPress(.return) {
          .handled
        }
    }
    .padding(28)
    .frame(width: 640, alignment: .leading)
    .contentSurface()
    .task {
      await Task.yield()
      isAttemptFocused = true
    }
  }
}

private struct ReviewFlipCard<Front: View, Back: View>: View {
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

  let isFlipped: Bool
  let isBackFaceInteractive: Bool
  let onFlip: () -> Void
  let onSpeak: () -> Void
  let front: Front
  let back: Back

  init(
    isFlipped: Bool,
    isBackFaceInteractive: Bool,
    onFlip: @escaping () -> Void,
    onSpeak: @escaping () -> Void,
    @ViewBuilder front: () -> Front,
    @ViewBuilder back: () -> Back
  ) {
    self.isFlipped = isFlipped
    self.isBackFaceInteractive = isBackFaceInteractive
    self.onFlip = onFlip
    self.onSpeak = onSpeak
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
    .shadow(color: .black.opacity(0.12), radius: 18)
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
    .keyboardShortcut(.space, modifiers: [])
    .disabled(isFlipped)
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
      .background {
        Button(action: onSpeak) {
          EmptyView()
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!isFlipped)
        .accessibilityHidden(true)
      }
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
        axis: (x: 1, y: 0, z: 0),
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

  fileprivate var shortcut: KeyEquivalent {
    switch self {
    case .forgot:
      "h"
    case .hard:
      "j"
    case .remembered:
      "k"
    case .easy:
      "l"
    }
  }
}

private struct SummaryCard: View {
  let title: String
  let value: Int
  let systemImage: String
  var systemImageLocale: Locale? = nil
  let tint: Color

  var body: some View {
    HStack {
      systemIcon
        .font(.system(size: 36, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 36)
        .padding(.horizontal, 8)

      Spacer()

      VStack(alignment: .trailing, spacing: 16) {
        Text(LocalizedStringKey(title))
          .font(.callout)
          .foregroundStyle(.secondary)
        Text(value, format: .number)
          .font(.system(size: 30, weight: .semibold, design: .rounded))
          .contentTransition(.numericText())
      }

    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentSurface()
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var systemIcon: some View {
    if let systemImageLocale {
      Image(systemName: systemImage)
        .environment(\.locale, systemImageLocale)
    } else {
      Image(systemName: systemImage)
    }
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

  #Preview("例句生词高亮") {
    HighlightedExampleSentence(
      sentence: "Finding this quiet bookstore was pure serendipity.",
      vocabulary: "serendipity"
    )
    .font(.title3)
    .italic()
    .padding()
    .frame(width: 480)
  }

  #Preview("拼写测验") {
    SpellingReviewPreview()
  }
#endif
