import SwiftUI
import AppKit

/// The composer mic control. A tap starts or stops a voice turn. While recording it becomes a
/// filled stop button wrapped in a soft pulsing ring, so it's unmistakable that Togi is listening.
struct VoiceMicButton: View {
    @ObservedObject var voice: VoiceSession
    var disabled: Bool = false

    private var recording: Bool { voice.isMicActive }

    var body: some View {
        Button(action: voice.toggle) {
            ZStack {
                if recording { PulseRing() }
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: recording ? 11 : 13, weight: .bold))
                    .foregroundStyle(recording ? Color.white : BogiColor.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        recording ? AnyShapeStyle(BogiColor.primary) : AnyShapeStyle(.ultraThinMaterial),
                        in: Circle()
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(recording ? "stop recording" : "talk to togi")
        .animation(.easeInOut(duration: 0.2), value: recording)
    }
}

/// Expanding, fading ring that signals active recording.
private struct PulseRing: View {
    @State private var animate = false
    var body: some View {
        Circle()
            .stroke(BogiColor.primary.opacity(0.45), lineWidth: 2)
            .frame(width: 30, height: 30)
            .scaleEffect(animate ? 1.5 : 0.95)
            .opacity(animate ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { animate = true }
            }
    }
}

/// The live voice strip beneath the composer: status, the recording waveform, your live
/// caption, Togi's reply, the booked-event confirmation with Undo, or a clear permission
/// prompt. Renders nothing when idle, so it takes no space.
struct VoiceStrip: View {
    @ObservedObject var voice: VoiceSession

    var body: some View {
        if voice.phase == .idle {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                statusRow
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.22), value: voice.phase)
        }
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: 8) {
            indicator
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(voice.phase == .denied || voice.phase == .error ? Color.orange : BogiColor.muted)
            Spacer(minLength: 4)
            if voice.phase == .listening || voice.phase == .speaking || voice.phase == .thinking {
                Button(action: voice.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BogiColor.muted)
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("stop")
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch voice.phase {
        case .listening:
            RecordingDot()
        case .thinking:
            ProgressView().controlSize(.small)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(BogiColor.primary)
        case .scheduled:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(BogiColor.primary)
        case .denied, .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    // MARK: - Body content per phase

    @ViewBuilder
    private var content: some View {
        switch voice.phase {
        case .listening:
            Text(voice.liveTranscript.isEmpty ? "go ahead, i'm listening" : voice.liveTranscript)
                .font(.callout)
                .foregroundStyle(voice.liveTranscript.isEmpty ? BogiColor.muted : BogiColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .scheduled:
            if let event = voice.lastEvent { scheduledRow(event) }
        case .denied:
            deniedBlock
        default:
            if !voice.togiLine.isEmpty {
                Text(voice.togiLine)
                    .font(.callout)
                    .foregroundStyle(BogiColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deniedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(voice.togiLine.isEmpty ? "togi needs microphone and speech access to hear you." : voice.togiLine)
                .font(.callout)
                .foregroundStyle(BogiColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: Self.openPrivacySettings) {
                Text("open settings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(BogiColor.primary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func scheduledRow(_ event: VoiceSession.Scheduled) -> some View {
        HStack(alignment: .top, spacing: 10) {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var statusText: String {
        switch voice.phase {
        case .idle:      return ""
        case .listening: return "recording"
        case .thinking:  return "togi is thinking…"
        case .speaking:  return "togi is speaking…"
        case .waiting:   return "your turn"
        case .scheduled: return "added to your calendar"
        case .chatting:  return "togi"
        case .denied:    return "permission needed"
        case .error:     return "something went wrong"
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
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

/// A small pulsing dot that reads as "recording" beside the status text.
private struct RecordingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(BogiColor.primary)
            .frame(width: 9, height: 9)
            .opacity(on ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
