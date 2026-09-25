import AVFoundation

enum AudioFeedback {
    private static var player: AVAudioPlayer?

    static func play(isEnabled: Bool) {
        let resourceName = isEnabled ? "ACTIVADA" : "DESACTIVADA"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "wav") else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            player = nil
        }
    }
}