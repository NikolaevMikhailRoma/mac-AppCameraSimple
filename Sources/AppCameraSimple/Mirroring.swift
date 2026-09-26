@preconcurrency import AVFoundation

extension AVCaptureConnection {
    /// Both guards are load-bearing: setting `isVideoMirrored` throws an
    /// uncatchable ObjC exception if mirroring is unsupported or automatic
    /// adjustment is still on.
    func setMirrored(_ mirrored: Bool) {
        guard isVideoMirroringSupported else { return }
        automaticallyAdjustsVideoMirroring = false
        isVideoMirrored = mirrored
    }
}
