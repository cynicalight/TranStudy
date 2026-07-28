import SwiftUI

struct TodayReviewView: View {
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
      if shell.isReviewAnswerVisible {
        reviewAnswer(item)
          .padding(28)
          .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
          .contentSurface()
      } else {
        Button {
          shell.revealCurrentReviewAnswer()
        } label: {
          Text(item.canonicalForm)
            .font(.system(size: 48, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .contentSurface()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("显示完整释义和例句")
      }

      if shell.selectedReviewRating == nil {
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
            .disabled(shell.isReviewRating)
          }
        }
      } else {
        Button {
          shell.advanceToNextReview()
        } label: {
          Label("下一个", systemImage: "arrow.right")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
    }
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
