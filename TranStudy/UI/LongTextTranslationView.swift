import AppKit
import Foundation
import SwiftUI

struct LongTextTranslationView: View {
  let shell: ApplicationShell
  let result: LongTextTranslationResult
  let onTranslateSelection: (NSRange) -> Void
  let onAddSentence: (NSRange) -> Void
  private let tokens: [LongTextWordToken]
  @State private var selectedTokenRange: ClosedRange<Int>?
  @State private var sourceContentHeight: CGFloat = 32
  @State private var translatedContentHeight: CGFloat = 24

  init(
    shell: ApplicationShell,
    result: LongTextTranslationResult,
    onTranslateSelection: @escaping (NSRange) -> Void,
    onAddSentence: @escaping (NSRange) -> Void
  ) {
    self.shell = shell
    self.result = result
    self.onTranslateSelection = onTranslateSelection
    self.onAddSentence = onAddSentence
    tokens = LongTextWordToken.tokenize(result.sourceText)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        ScrollView {
          WordCapsuleFlowLayout(spacing: 3) {
            ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
              HStack(spacing: 1) {
                if !token.leadingPunctuation.isEmpty {
                  Text(token.leadingPunctuation)
                }
                Button {
                  updateSelection(with: index)
                } label: {
                  Text(token.word)
                    .font(.body)
                    .foregroundStyle(isSelected(index) ? Color.white : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                      Capsule(style: .continuous)
                        .fill(
                          isSelected(index)
                            ? Color.accentColor
                            : Color.secondary.opacity(0.12)
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(token.word)
                .accessibilityAddTraits(isSelected(index) ? .isSelected : [])
                if !token.trailingPunctuation.isEmpty {
                  Text(token.trailingPunctuation)
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
          } action: { height in
            sourceContentHeight = height
          }
        }
        .frame(height: blockHeight(for: sourceContentHeight))
        .background(.background.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      HStack {
        CopyTextButton(text: result.sourceText, accessibilityLabel: "复制原文")
        Spacer()
        if shell.isSentenceCardsEnabled {
          Button {
            onAddSentence(selectedRange)
          } label: {
            if shell.isAddingSentenceCard {
              ProgressView()
                .controlSize(.small)
            } else {
              Label("加入所在句", systemImage: "quote.bubble")
            }
          }
          .buttonStyle(.bordered)
          .disabled(!shell.canAddLongTextSentence(selectedRange))
        }
        Button {
          onTranslateSelection(selectedRange)
        } label: {
          Label("学习选中词", systemImage: "text.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .environment(\.controlActiveState, .active)
        .disabled(!shell.canTranslateLongTextSelection(selectedRange))
      }

      if shell.isSentenceCardsEnabled, let status = shell.sentenceCardAdditionStatus {
        Label {
          Text(status == .added ? "已加入句子卡" : "加入失败，请重试")
        } icon: {
          Image(
            systemName: status == .added
              ? "checkmark.circle.fill"
              : "exclamationmark.circle"
          )
        }
        .font(.caption)
        .foregroundStyle(status == .added ? .green : .red)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }

      Divider()

      VStack(alignment: .leading, spacing: 5) {
        ScrollView {
          Text(result.translatedText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
              proxy.size.height
            } action: { height in
              translatedContentHeight = height
            }
        }
        .frame(height: blockHeight(for: translatedContentHeight))
        HStack {
          CopyTextButton(text: result.translatedText, accessibilityLabel: "复制译文")
          Spacer()
          Label("长文本译文不会自动加入学习", systemImage: "lock.open.display")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(4)
    .onChange(of: result.sourceText) {
      selectedTokenRange = nil
    }
    .onChange(of: selectedTokenRange) {
      shell.clearSentenceCardAdditionStatus()
    }
  }

  private func blockHeight(for contentHeight: CGFloat) -> CGFloat {
    min(max(contentHeight, 1), 180)
  }

  private var selectedRange: NSRange {
    guard
      let selectedTokenRange,
      tokens.indices.contains(selectedTokenRange.lowerBound),
      tokens.indices.contains(selectedTokenRange.upperBound)
    else {
      return NSRange(location: 0, length: 0)
    }
    let firstRange = tokens[selectedTokenRange.lowerBound].sourceRange
    let lastRange = tokens[selectedTokenRange.upperBound].sourceRange
    return NSRange(
      location: firstRange.location,
      length: NSMaxRange(lastRange) - firstRange.location
    )
  }

  private func isSelected(_ index: Int) -> Bool {
    selectedTokenRange?.contains(index) == true
  }

  private func updateSelection(with index: Int) {
    guard let currentRange = selectedTokenRange else {
      selectedTokenRange = index...index
      return
    }

    if currentRange.lowerBound == index {
      selectedTokenRange =
        currentRange.count == 1
        ? nil
        : (currentRange.lowerBound + 1)...currentRange.upperBound
      return
    }

    if currentRange.upperBound == index {
      selectedTokenRange = currentRange.lowerBound...(currentRange.upperBound - 1)
      return
    }

    let expandedRange =
      min(currentRange.lowerBound, index)...max(currentRange.upperBound, index)
    if expandedRange.count <= 8 {
      selectedTokenRange = expandedRange
    }
  }
}

private struct CopyTextButton: View {
  let text: String
  let accessibilityLabel: String

  var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    } label: {
      Image(systemName: "doc.on.doc")
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .accessibilityLabel(accessibilityLabel)
    .help(accessibilityLabel)
  }
}

private struct LongTextWordToken: Identifiable {
  let id: Int
  let word: String
  let leadingPunctuation: String
  let trailingPunctuation: String
  let sourceRange: NSRange

  static func tokenize(_ text: String) -> [Self] {
    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    guard
      let expression = try? NSRegularExpression(
        pattern: #"\p{L}[\p{L}\p{M}\p{N}]*(?:['’\-][\p{L}\p{M}\p{N}]+)*|\p{N}+"#
      )
    else {
      return []
    }

    let matches = expression.matches(in: text, range: fullRange)
    return matches.enumerated().map { index, match in
      let previousLocation =
        index > 0
        ? NSMaxRange(matches[index - 1].range)
        : 0
      let nextLocation =
        matches.indices.contains(index + 1)
        ? matches[index + 1].range.location
        : source.length
      let leadingSeparator = source.substring(
        with: NSRange(
          location: previousLocation,
          length: match.range.location - previousLocation
        )
      )
      let trailingSeparator = source.substring(
        with: NSRange(
          location: NSMaxRange(match.range),
          length: max(0, nextLocation - NSMaxRange(match.range))
        )
      )
      let leadingPunctuation =
        index == 0 || leadingSeparator.contains(where: \.isWhitespace)
        ? String(
          leadingSeparator.reversed().prefix { !$0.isWhitespace }.reversed()
        )
        : ""
      let trailingPunctuation = String(
        trailingSeparator.prefix { !$0.isWhitespace }
      )
      let word = source.substring(with: match.range)

      return Self(
        id: match.range.location,
        word: word,
        leadingPunctuation: leadingPunctuation,
        trailingPunctuation: trailingPunctuation,
        sourceRange: match.range
      )
    }
  }
}

private struct WordCapsuleFlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let result = layout(subviews: subviews, width: proposal.width ?? .infinity)
    return CGSize(width: proposal.width ?? result.width, height: result.height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let result = layout(subviews: subviews, width: bounds.width)
    for (index, point) in result.points.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
        anchor: .topLeading,
        proposal: .unspecified
      )
    }
  }

  private func layout(subviews: Subviews, width: CGFloat) -> LayoutResult {
    var points: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var contentWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      points.append(CGPoint(x: x, y: y))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      contentWidth = max(contentWidth, x - spacing)
    }

    return LayoutResult(
      points: points,
      width: contentWidth,
      height: subviews.isEmpty ? 0 : y + rowHeight
    )
  }

  private struct LayoutResult {
    let points: [CGPoint]
    let width: CGFloat
    let height: CGFloat
  }
}

#if DEBUG
  #Preview("长文本翻译") {
    LongTextTranslationView(
      shell: PreviewFactory.makeShell(),
      result: LongTextTranslationResult(
        sourceText: "The team remained resilient after the setback. They kept improving.",
        translatedText: "团队在遭遇挫折后依然保持韧性。他们继续不断进步。"
      ),
      onTranslateSelection: { _ in },
      onAddSentence: { _ in }
    )
    .padding()
    .frame(width: 500)
  }
#endif
