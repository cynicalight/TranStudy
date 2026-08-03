import AppKit
import SwiftUI

enum TranStudyDesign {
  static let pageWidth: CGFloat = 820
  static let cornerRadius: CGFloat = 16
  static let accentNSColor = NSColor(
    srgbRed: 232.0 / 255.0,
    green: 127.0 / 255.0,
    blue: 79.0 / 255.0,
    alpha: 1
  )
  static let accentColor = Color(nsColor: accentNSColor)
  static let accentForegroundColor = Color(
    red: 44.0 / 255.0,
    green: 23.0 / 255.0,
    blue: 16.0 / 255.0
  )
}

struct TranStudySegmentedControl<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option
  let label: (Option) -> String
  let tint: (Option) -> Color
  let selectedForeground: (Option) -> Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  init(
    options: [Option],
    selection: Binding<Option>,
    label: @escaping (Option) -> String,
    tint: @escaping (Option) -> Color = { _ in TranStudyDesign.accentColor },
    selectedForeground: @escaping (Option) -> Color = { _ in
      TranStudyDesign.accentForegroundColor
    }
  ) {
    self.options = options
    _selection = selection
    self.label = label
    self.tint = tint
    self.selectedForeground = selectedForeground
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        segment(for: option)
      }
    }
    .padding(3)
    .adaptiveGlassCapsule()
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
      Text(LocalizedStringKey(label(option)))
        .font(.subheadline)
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundStyle(isSelected ? selectedForeground(option) : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(.capsule)
        .background {
          if isSelected {
            Capsule()
              .fill(tint(option))
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
  var tint: Color = TranStudyDesign.accentColor

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 42, height: 42)
        .background(
          tint.opacity(0.1),
          in: .rect(cornerRadius: 12)
        )

      VStack(alignment: .leading, spacing: 3) {
        Text(LocalizedStringKey(title))
          .font(.title2.weight(.semibold))
        Text(LocalizedStringKey(subtitle))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

struct SpeechButton: View {
  let text: String
  let speak: (String) -> Void

  var body: some View {
    Button {
      speak(text)
    } label: {
      Image(systemName: "speaker.wave.2.fill")
    }
    .buttonStyle(.borderless)
    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    .help("朗读")
    .accessibilityLabel("朗读")
  }
}

extension View {
  func contentSurface(cornerRadius: CGFloat = TranStudyDesign.cornerRadius) -> some View {
    modifier(ContentSurfaceModifier(cornerRadius: cornerRadius))
  }

  func adaptiveGlass(cornerRadius: CGFloat = 12) -> some View {
    modifier(
      AdaptiveGlassModifier(
        shape: RoundedRectangle(cornerRadius: cornerRadius),
        tint: nil
      ))
  }

  func adaptiveGlassCapsule() -> some View {
    modifier(AdaptiveGlassModifier(shape: Capsule(), tint: nil))
  }

  func adaptiveTintedGlass(
    cornerRadius: CGFloat = 12,
    tint: Color = TranStudyDesign.accentColor
  ) -> some View {
    modifier(
      AdaptiveGlassModifier(
        shape: RoundedRectangle(cornerRadius: cornerRadius),
        tint: tint
      ))
  }

  func adaptiveTintedGlassCapsule(
    tint: Color = TranStudyDesign.accentColor
  ) -> some View {
    modifier(AdaptiveGlassModifier(shape: Capsule(), tint: tint))
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

private struct AdaptiveGlassModifier<GlassShape: Shape>: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  let shape: GlassShape
  let tint: Color?

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content
        .background(tint ?? .clear, in: shape)
        .background(
          Color(nsColor: .windowBackgroundColor),
          in: shape
        )
        .overlay {
          shape
            .stroke(.separator, lineWidth: 1)
        }
    } else if #available(macOS 26, *), let tint {
      content
        .glassEffect(.regular.tint(tint).interactive(), in: shape)
    } else if #available(macOS 26, *) {
      content
        .glassEffect(.regular, in: shape)
    } else {
      content
        .background(tint?.opacity(0.78) ?? .clear, in: shape)
        .background(.regularMaterial, in: shape)
        .overlay {
          shape
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
