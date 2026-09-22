@preconcurrency import AVFoundation

extension AVCaptureConnection {
    /// Mirrors the video about its vertical axis. Both guards are load-bearing:
    /// `isVideoMirrored` throws if mirroring is unsupported, and throws again if
    /// `automaticallyAdjustsVideoMirroring` is still on, so that has to be turned
    /// off first. Both are ObjC exceptions, i.e. an uncatchable crash from Swift.
    ///
    /// Nothing is flipped pixel by pixel: the mirror is recorded as an Exif
    /// orientation tag on photos and as the display matrix of the video track,
    /// which both AVFoundation and ffmpeg apply on playback. Only a player that
    /// ignores the matrix outright would show such a recording unmirrored.
    func setMirrored(_ mirrored: Bool) {
        guard isVideoMirroringSupported else { return }
        automaticallyAdjustsVideoMirroring = false
        isVideoMirrored = mirrored
    }
}
