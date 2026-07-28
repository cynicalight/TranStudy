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

        reviewStatus
      }
      .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .navigationTitle("今日复习")
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
