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

    func capture() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = (error == nil) ? photo.fileDataRepresentation() : nil
        Task { @MainActor [weak self] in
            self?.save(data)
        }
    }

    private func save(_ data: Data?) {
        guard let data else {
            onFinished?(.failure(PhotoError.noData))
            return
        }
        let url = folder.resolvedFolder()
            .appendingPathComponent(Filenames.captureName(ext: "jpg"))
        do {
            try data.write(to: url)
            onFinished?(.success(url))
        } catch {
            onFinished?(.failure(error))
        }
    }
}
