@preconcurrency import AVFoundation
import AppCameraSimpleCore

extension AVCaptureOutput {
    /// The camera feeding this output: its active format, which is what the
    /// photo and video outputs deliver on the Mac, and its top frame rate.
    var cameraFormat: CameraFormat? {
        guard let device = (connection(with: .video)?.inputPorts.first?.input as? AVCaptureDeviceInput)?.device else {
            return nil
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let frame = device.activeVideoMinFrameDuration
        return CameraFormat(width: Int(dimensions.width), height: Int(dimensions.height),
                            fps: frame.isValid && frame.seconds > 0 ? 1 / frame.seconds : 30)
    }
}
