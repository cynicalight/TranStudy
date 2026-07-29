import AppKit
import SwiftUI

struct LongTextTranslationView: View {
  let shell: ApplicationShell
  let result: LongTextTranslationResult
  let onTranslateSelection: (NSRange) -> Void
  @State private var selectedRange = NSRange(location: 0, length: 0)

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text("英文原文")
          .font(.caption)
          .foregroundStyle(.secondary)
        SelectableLongText(text: result.sourceText, selectedRange: $selectedRange)
          .frame(height: 115)
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(.separator.opacity(0.7))
          }
      }

      HStack {
        Text(selectionHint)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          onTranslateSelection(selectedRange)
        } label: {
          Label("学习选中词", systemImage: "text.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!shell.canTranslateLongTextSelection(selectedRange))
      }

      Divider()

      VStack(alignment: .leading, spacing: 5) {
        Text("中文译文")
          .font(.caption)
          .foregroundStyle(.secondary)
        ScrollView {
          Text(result.translatedText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 115)
      }

      Label("长文本译文不会自动加入学习", systemImage: "lock.open.display")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(4)
  }

  private var selectionHint: String {
    selectedRange.length == 0
      ? "在英文原文中选择一个单词或短语"
      : "选区需为不超过 8 个词的单词或短语"
  }
}

private struct SelectableLongText: NSViewRepresentable {
  let text: String
  @Binding var selectedRange: NSRange

  func makeCoordinator() -> Coordinator {
    Coordinator(selectedRange: $selectedRange)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    let contentSize = scrollView.contentSize
    let textView = NSTextView(
      frame: NSRect(origin: .zero, size: contentSize)
    )
    textView.delegate = context.coordinator
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.drawsBackground = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.font = .preferredFont(forTextStyle: .body)
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: contentSize.width,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.string = text

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else {
      return
    }
    if textView.string != text {
      textView.string = text
      let emptyRange = NSRange(location: 0, length: 0)
      textView.setSelectedRange(emptyRange)
      context.coordinator.publishSelectedRange(emptyRange)
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding private var selectedRange: NSRange
    private var pendingSelectedRange: NSRange?

    init(selectedRange: Binding<NSRange>) {
      _selectedRange = selectedRange
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else {
        return
      }
      publishSelectedRange(textView.selectedRange())
    }

    func publishSelectedRange(_ range: NSRange) {
      guard selectedRange != range, pendingSelectedRange != range else {
        return
      }
      pendingSelectedRange = range

      DispatchQueue.main.async { [weak self] in
        guard let self, self.pendingSelectedRange == range else {
          return
        }
        self.pendingSelectedRange = nil
        guard self.selectedRange != range else {
          return
        }
        self.selectedRange = range
      }
    }
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
      onTranslateSelection: { _ in }
    )
    .padding()
    .frame(width: 500, height: 430)
  }
#endif
