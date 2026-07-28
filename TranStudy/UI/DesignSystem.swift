import AppKit
import SwiftUI

enum TranStudyDesign {
  static let pageWidth: CGFloat = 820
  static let cornerRadius: CGFloat = 16
}

struct TranStudySegmentedControl<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option
  let label: (Option) -> String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        segment(for: option)
      }
    }
    .padding(3)
    .background(
      Color(nsColor: .controlBackgroundColor),
      in: .rect(cornerRadius: 10)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(.separator.opacity(0.35), lineWidth: 1)
    }
  }

  private func segment(for option: Option) -> some View {
    let isSelected = selection == option

    return Button {
      guard !isSelected else {
        return
      }

      withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
        selection = option
      }
      NSHapticFeedbackManager.defaultPerformer.perform(
        .alignment,
        performanceTime: .now
      )
    } label: {
      Text(label(option))
        .font(.subheadline)
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundStyle(isSelected ? Color.white : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(.rect)
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.accentColor)
              .matchedGeometryEffect(
                id: "selectedSegment",
                in: selectionNamespace
              )
          }
        }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

struct PageHeader: View {
  let title: String
  let subtitle: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 42, height: 42)
        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.title2.weight(.semibold))
        Text(subtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

extension View {
  func contentSurface(cornerRadius: CGFloat = TranStudyDesign.cornerRadius) -> some View {
    modifier(ContentSurfaceModifier(cornerRadius: cornerRadius))
  }

  func adaptiveGlass(cornerRadius: CGFloat = 12) -> some View {
    modifier(AdaptiveGlassModifier(cornerRadius: cornerRadius))
  }
}

private struct ContentSurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(
        Color(nsColor: .controlBackgroundColor),
        in: .rect(cornerRadius: cornerRadius)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(.separator.opacity(0.35), lineWidth: 1)
      }
  }
}

private struct AdaptiveGlassModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  let cornerRadius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content
        .background(
          Color(nsColor: .windowBackgroundColor),
          in: .rect(cornerRadius: cornerRadius)
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(.separator, lineWidth: 1)
        }
    } else if #available(macOS 26, *) {
      content
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    } else {
      content
        .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
    }
  }
}

#if DEBUG
  #Preview("分段选择器") {
    TranStudySegmentedControl(
      options: TranslationPanelPosition.allCases,
      selection: .constant(.topTrailing),
      label: \.title
    )
    .padding()
    .frame(width: 420)
  }

  #Preview("页面标题") {
    PageHeader(
      title: "今日复习",
      subtitle: "把今天该记住的内容，变成一个轻松完成的小目标。",
      systemImage: "rectangle.stack.fill"
    )
    .padding()
    .frame(width: 520)
  }
#endif
