import SwiftUI

/// The mic button that lives in the composer. Active (sky-filled, waveform) while listening.
/// Observes the session so its look tracks the live phase.
struct VoiceMicButton: View {
    @ObservedObject var voice: VoiceSession
    var disabled: Bool = false

    var body: some View {
        Button(action: voice.toggle) {
            Image(systemName: voice.isMicActive ? "waveform" : "mic.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(voice.isMicActive ? Color.white : BogiColor.primary)
                .frame(width: 28, height: 28)
                .background(
                    voice.isMicActive ? AnyShapeStyle(BogiColor.primary) : AnyShapeStyle(.ultraThinMaterial),
                    in: Circle()
                )
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("talk to togi")
    }
}

/// A compact strip that surfaces the live voice exchange beneath the composer: what Togi is
/// doing, the live caption of what you're saying, Togi's spoken line, and — once it books
/// something — a confirmation row with Undo. Renders nothing when idle, so it takes no space.
struct VoiceStrip: View {
    @ObservedObject var voice: VoiceSession

    var body: some View {
        if voice.phase == .idle {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                statusRow

                if !voice.togiLine.isEmpty, voice.phase != .scheduled {
                    Text(voice.togiLine)
                        .font(.callout)
                        .foregroundStyle(BogiColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if voice.phase == .listening, !voice.liveTranscript.isEmpty {
                    Text(voice.liveTranscript)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(BogiColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if voice.phase == .scheduled, let event = voice.lastEvent {
                    scheduledRow(event)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: voice.phase)
        }
    }

    // MARK: - Rows

    private var statusRow: some View {
        HStack(spacing: 8) {
            indicator
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BogiColor.muted)
            Spacer(minLength: 4)
            if voice.phase == .listening || voice.phase == .speaking || voice.phase == .thinking {
                Button(action: voice.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BogiColor.muted)
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("stop")
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch voice.phase {
        case .thinking:
            ProgressView().controlSize(.small)
        case .listening:
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BogiColor.primary)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BogiColor.primary)
        case .scheduled:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BogiColor.primary)
        case .denied, .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private func scheduledRow(_ event: VoiceSession.Scheduled) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(BogiColor.ink)
                    .lineLimit(2)
                Text(Self.when(event.start))
                    .font(.caption)
                    .foregroundStyle(BogiColor.muted)
            }
            Spacer(minLength: 8)
            Button(action: voice.undo) {
                Text("undo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BogiColor.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var statusText: String {
        switch voice.phase {
        case .idle:      return ""
        case .listening: return "listening…"
        case .thinking:  return "togi is thinking…"
        case .speaking:  return "togi is speaking…"
        case .scheduled: return "added to your calendar"
        case .chatting:  return "togi"
        case .denied:    return "permission needed"
        case .error:     return "something went wrong"
        }
    }

    private static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
