import AVFoundation

@MainActor
final class SystemSpeechPlayer: SpeechPlaying {
  private let synthesizer = AVSpeechSynthesizer()

  var availableVoices: [SpeechVoice] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("en") }
      .map {
        SpeechVoice(
          identifier: $0.identifier,
          name: $0.name,
          language: $0.language
        )
      }
      .sorted {
        if $0.language == $1.language {
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return $0.language < $1.language
      }
  }

  func speak(_ text: String) {
    speak(text, voiceIdentifier: nil, rate: LanguageAndSpeechPreferences.default.speechRate)
  }

  func speak(
    _ text: String,
    voiceIdentifier: String?,
    rate: Float
  ) {
    let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      return
    }

    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: content)
    utterance.voice =
      voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
      ?? AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = min(
      max(rate, AVSpeechUtteranceMinimumSpeechRate),
      AVSpeechUtteranceMaximumSpeechRate
    )
    synthesizer.speak(utterance)
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
  }
}
