import AVFoundation

/// A soft generative ambient pad: a few detuned sine partials at low volume with a slow
/// swell, faded in and out. Off by default; the calm overlay toggles it. Output only, so
/// no entitlement is required. Deliberately quiet — a presence, not music.
final class AmbientPad {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var running = false

    // Oscillator + envelope state, read/written from the audio render thread.
    private var p1 = 0.0, p2 = 0.0, p3 = 0.0, lfo = 0.0
    private var amp = 0.0
    private var target = 0.0

    /// Toggle the pad. Returns the new on/off state.
    func toggle() -> Bool {
        if running { stop() } else { start() }
        return running
    }

    func start() {
        guard !running else { return }
        let sampleRate = max(engine.outputNode.outputFormat(forBus: 0).sampleRate, 44_100)
        let twoPi = 2.0 * Double.pi

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, ablPointer in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            for frame in 0..<Int(frameCount) {
                // Glide the amplitude toward its target for a gentle fade.
                self.amp += (self.target - self.amp) * 0.0004
                self.lfo += twoPi * 0.05 / sampleRate
                if self.lfo > twoPi { self.lfo -= twoPi }
                let swell = 0.82 + 0.18 * sin(self.lfo)

                self.p1 += twoPi * 146.83 / sampleRate   // D3
                self.p2 += twoPi * 220.00 / sampleRate   // A3
                self.p3 += twoPi * 110.00 / sampleRate   // A2 sub
                if self.p1 > twoPi { self.p1 -= twoPi }
                if self.p2 > twoPi { self.p2 -= twoPi }
                if self.p3 > twoPi { self.p3 -= twoPi }

                let mix = sin(self.p1) * 0.5 + sin(self.p2) * 0.28 + sin(self.p3) * 0.55
                let value = Float(mix * self.amp * swell)
                for buffer in abl {
                    if let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        ptr[frame] = value
                    }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
        source = node
        do {
            try engine.start()
            target = 0.05
            running = true
        } catch {
            engine.detach(node)
            source = nil
        }
    }

    func stop() {
        guard running else { return }
        running = false
        target = 0.0
        let engine = self.engine
        let node = source
        source = nil
        // Let the amplitude fade out before pausing the engine.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            engine.pause()
            if let node { engine.detach(node) }
        }
    }
}
