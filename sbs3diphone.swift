

import Foundation
import AVFoundation
import Photos // For saving to Photos library (optional)
import ffmpegkit

// MARK: - VideoJoinerDelegate Protocol

/// A delegate protocol to communicate the status of the video joining operation.
protocol VideoJoinerDelegate: AnyObject {
    /// Called when the video joining operation is successful.
    /// - Parameter outputPath: The file path of the successfully joined video.
    func videoJoinerDidSucceed(outputPath: String)

    /// Called when the video joining operation fails.
    /// - Parameter errorMessage: A descriptive error message.
    func videoJoinerDidFail(errorMessage: String)

    /// Optional: Called to provide progress updates during the video joining operation.
    /// - Parameters:
    ///   - time: The current processing time in milliseconds.
    ///   - duration: The total duration of the video (may not always be accurate for complex filters).
    func videoJoinerDidUpdateProgress(time: Int64, duration: Int64)
}

// MARK: - VideoJoiner Class

/// A utility class for iOS to join two video files side-by-side using mobile-ffmpeg-kit-ios.
/// This class assumes mobile-ffmpeg-kit-ios is properly integrated into the iOS project.
class VideoJoiner {

    weak var delegate: VideoJoinerDelegate?

    /// Initializes the VideoJoiner.
    init() {}

    /**
     Joins two video files side-by-side into a new output video using FFmpeg-Kit.
     This operation is asynchronous. Results are delivered via the `VideoJoinerDelegate`.

     - Parameters:
       - video1URL: The `URL` for the first input video. This should be a file URL.
       - video2URL: The `URL` for the second input video. This should be a file URL.
       - outputFileName: The desired file name for the output joined video (e.g., "output_side_by_side.mp4").
                         The output will be saved in the app's temporary directory.
     */
    func joinVideosSideBySide(video1URL: URL, video2URL: URL, outputFileName: String) {

        // Validate input file paths
        guard FileManager.default.fileExists(atPath: video1URL.path) else {
            delegate?.videoJoinerDidFail(errorMessage: "Video 1 file not found: \(video1URL.lastPathComponent)")
            return
        }
        guard FileManager.default.fileExists(atPath: video2URL.path) else {
            delegate?.videoJoinerDidFail(errorMessage: "Video 2 file not found: \(video2URL.lastPathComponent)")
            return
        }

        // Define the output file path in the app's temporary directory
        // This is a good place for temporary files before moving them to a permanent location
        let outputDir = FileManager.default.temporaryDirectory
        let outputPath = outputDir.appendingPathComponent(outputFileName).path

        // Ensure the output directory exists (though temporaryDirectory usually does)
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                delegate?.videoJoinerDidFail(errorMessage: "Failed to create output directory: \(error.localizedDescription)")
                return
            }
        }

        // Construct the FFmpeg command for side-by-side joining
        // The filter_complex command scales videos to a common height and stacks them horizontally, then merges audio.
        // It's important to escape paths properly for FFmpeg, especially if they contain spaces.
        let ffmpegCommand = String(format:
            "-i \"%@\" -i \"%@\" -filter_complex " +
            "\"[0:v]scale=iw*min(ih\\/ih,ih\\/ih):ih,pad=iw*min(ih\\/ih,ih\\/ih):ih:(ow-iw)/2:(oh-ih)/2[v0];" +
            "[1:v]scale=iw*min(ih\\/ih,ih\\/ih):ih,pad=iw*min(ih\\/ih,ih\\/ih):ih:(ow-iw)/2:(oh-ih)/2[v1];" +
            "[v0][v1]hstack=inputs=2[v];" +
            "[0:a][1:a]amerge=inputs=2[a]\" " +
            "-map \"[v]\" -map \"[a]\" -ac 2 -y \"%@\"",
            video1URL.path, video2URL.path, outputPath
        )

        print("Executing FFmpeg command: \(ffmpegCommand)")

        // Execute the FFmpeg command asynchronously using FFmpegKit
        FFmpegKit.executeAsync(ffmpegCommand, withCallback: { session in
            // This callback runs on a background thread.
            // Dispatch to the main thread if updating UI.
            let returnCode = session?.getReturnCode()

            if ReturnCode.isSuccess(returnCode) {
                print("FFmpeg command executed successfully. Output: \(outputPath)")
                DispatchQueue.main.async {
                    self.delegate?.videoJoinerDidSucceed(outputPath: outputPath)
                }
            } else if ReturnCode.isCancel(returnCode) {
                print("FFmpeg command cancelled.")
                DispatchQueue.main.async {
                    self.delegate?.videoJoinerDidFail(errorMessage: "Operation cancelled.")
                }
            } else {
                let errorMessage = session?.getFailStackTrace() ?? session?.getOutput() ?? "Unknown FFmpeg error."
                print("FFmpeg command failed with state \(session?.getState()?.rawValue ?? -1) and return code \(returnCode?.intValue ?? -1). Error: \(errorMessage)")
                DispatchQueue.main.async {
                    self.delegate?.videoJoinerDidFail(errorMessage: "FFmpeg failed: \(errorMessage)")
                }
            }
        }, withLogCallback: { log in
            // Optional: Handle FFmpeg logs for debugging
            // print("FFmpeg Log: \(log?.getMessage() ?? "")")
        }, withStatisticsCallback: { statistics in
            // Optional: Handle FFmpeg statistics for progress updates
            // let timeInMilliseconds = statistics?.getTime() ?? 0
            // let totalDuration = statistics?.getDuration() ?? 0
            // DispatchQueue.main.async {
            //     self.delegate?.videoJoinerDidUpdateProgress(time: timeInMilliseconds, duration: totalDuration)
            // }
        })
    }
}

// MARK: - Example Usage (e.g., in a ViewController)

/*
// In your ViewController.swift or similar file:

import UIKit
import MobileFFmpeg

class ViewController: UIViewController, VideoJoinerDelegate {

    private var videoJoiner: VideoJoiner?

    override func viewDidLoad() {
        super.viewDidLoad()
        videoJoiner = VideoJoiner()
        videoJoiner?.delegate = self
    }

    // Call this method when you want to start joining videos, e.g., from a button tap
    @IBAction func joinVideosButtonTapped(_ sender: UIButton) {
        // --- IMPORTANT: Replace these URLs with your actual video file URLs ---
        // For demonstration, these might be URLs to videos copied into the app's bundle
        // or fetched from the Photos library.
        // For real-world use, you'd typically get these from a UIImagePickerController
        // or a custom file picker.

        // Example: Using URLs from the app's bundle (for testing)
        guard let video1URL = Bundle.main.url(forResource: "video1", withExtension: "mp4"),
              let video2URL = Bundle.main.url(forResource: "video2", withExtension: "mp4") else {
            print("Error: Could not find video files in app bundle.")
            return
        }

        // Example: Using URLs from a sandboxed directory (e.g., Documents directory)
        // let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        // let video1URL = documentsPath.appendingPathComponent("my_video_1.mp4")
        // let video2URL = documentsPath.appendingPathComponent("my_video_2.mp4")

        let outputFileName = "joined_side_by_side.mp4"

        print("Starting video join process...")
        videoJoiner?.joinVideosSideBySide(video1URL: video1URL, video2URL: video2URL, outputFileName: outputFileName)
    }

    // MARK: - VideoJoinerDelegate Methods

    func videoJoinerDidSucceed(outputPath: String) {
        print("Video joined successfully! Output path: \(outputPath)")
        // You can now move this file to a permanent location,
        // display it, or save it to the Photos library.
        // Example: Saving to Photos library (requires "Privacy - Photo Library Additions Usage Description" in Info.plist)
        // saveVideoToPhotosLibrary(videoPath: outputPath)
    }

    func videoJoinerDidFail(errorMessage: String) {
        print("Video joining failed: \(errorMessage)")
        // Show an alert to the user
        let alert = UIAlertController(title: "Error", message: "Video joining failed: \(errorMessage)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    func videoJoinerDidUpdateProgress(time: Int64, duration: Int64) {
        // Update a UIProgressView or similar
        // print("Progress: \(time) / \(duration)")
    }

    // Helper function to save video to Photos Library
    private func saveVideoToPhotosLibrary(videoPath: String) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: videoPath))
        }) { success, error in
            if success {
                print("Video successfully saved to Photos Library.")
            } else {
                print("Error saving video to Photos Library: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
}
*/
