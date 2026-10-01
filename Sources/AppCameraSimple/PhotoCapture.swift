import Foundation
@preconcurrency import AVFoundation
import AppCameraSimpleCore

@MainActor
final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate {
    enum PhotoError: Error {
        case noData
    }

    var onFinished: ((Result<URL, Error>) -> Void)?

    private let output = AVCapturePhotoOutput()
    private let folder: SaveFolderStore

    init(folder: SaveFolderStore) {
        self.folder = folder
    }

    func configure(session: AVCaptureSession) {
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
    }

    /// Flips the pixels, so photos carry no Exif orientation tag.
    func setMirrored(_ mirrored: Bool) {
        output.connection(with: .video)?.setMirrored(mirrored)
    }

    /// The photo's size before scaling.
    var camera: CameraFormat? { output.cameraFormat }

    /// Asks for uncompressed pixels, so the chosen format is encoded once from
    /// the sensor data rather than re-encoded from the camera's own JPEG.
    func capture() {
        let bgra = kCVPixelFormatType_32BGRA
        let settings = output.availablePhotoPixelFormatTypes.contains(bgra)
            ? AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: bgra])
            : AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    /// Encodes here, off the main thread, with the options set at the moment
    /// the photo arrives.
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let options = PhotoOptions.stored()
        let data = (error == nil)
            ? photo.cgImageRepresentation().flatMap {
                PhotoExport.convert($0, options: options)
            }
            : nil
        Task { @MainActor [weak self] in
            self?.save(data, format: options.format)
        }
    }

    private func save(_ data: Data?, format: PhotoFormat) {
        guard let data else {
            onFinished?(.failure(PhotoError.noData))
            return
        }
        let url = folder.resolvedFolder()
            .appendingPathComponent(Filenames.captureName(ext: format.fileExtension))
        do {
            try data.write(to: url)
            onFinished?(.success(url))
        } catch {
            onFinished?(.failure(error))
        }
    }
}
