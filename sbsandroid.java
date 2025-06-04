import android.content.Context;
import android.net.Uri;
import android.util.Log;

import com.arthenica.ffmpegkit.FFmpegKit;
import com.arthenica.ffmpegkit.FFmpegSession;
import com.arthenica.ffmpegkit.ReturnCode;

import java.io.File;

/**
 * A utility class for Android to join two video files side-by-side using FFmpeg-Kit.
 * This class assumes FFmpeg-Kit is properly integrated into the Android project.
 */
public class AndroidVideoJoiner {

    private static final String TAG = "AndroidVideoJoiner";

    /**
     * Callback interface for video joining operation status.
     */
    public interface OnVideoJoinListener {
        void onVideoJoinSuccess(String outputPath);
        void onVideoJoinFailure(String errorMessage);
        void onVideoJoinProgress(long time, long duration); // Optional: for progress updates
    }

    private final Context context;
    private OnVideoJoinListener listener;

    public AndroidVideoJoiner(Context context) {
        this.context = context;
    }

    /**
     * Sets the listener for video joining events.
     * @param listener The listener to set.
     */
    public void setOnVideoJoinListener(OnVideoJoinListener listener) {
        this.listener = listener;
    }

    /**
     * Joins two video files side-by-side into a new output video using FFmpeg-Kit.
     * This operation is asynchronous and should be called from the main thread.
     * The results are delivered via the OnVideoJoinListener.
     *
     * @param video1Uri The Uri for the first input video.
     * @param video2Uri The Uri for the second input video.
     * @param outputFileName The desired file name for the output joined video (e.g., "output_side_by_side.mp4").
     * The output will be saved in the app's external files directory.
     */
    public void joinVideosSideBySide(Uri video1Uri, Uri video2Uri, String outputFileName) {
        // Resolve Uri to actual file paths if necessary.
        // For simplicity, this example assumes direct file paths or content URIs that FFmpeg-Kit can handle.
        // In a real app, you might need to copy content URI files to a temporary internal storage path
        // if FFmpeg-Kit cannot directly read them.
        String video1Path = video1Uri.getPath(); // This might need more robust handling for content Uris
        String video2Path = video2Uri.getPath(); // This might need more robust handling for content Uris

        // Define the output file path in the app's external files directory
        File outputDir = context.getExternalFilesDir(null); // Get app-specific external storage directory
        if (outputDir == null) {
            Log.e(TAG, "External files directory is null. Cannot proceed.");
            if (listener != null) {
                listener.onVideoJoinFailure("Failed to access external storage.");
            }
            return;
        }
        File outputFile = new File(outputDir, outputFileName);
        String outputPath = outputFile.getAbsolutePath();

        // Ensure the output directory exists
        if (!outputFile.getParentFile().exists()) {
            outputFile.getParentFile().mkdirs();
        }

        // Construct the FFmpeg command for side-by-side joining
        // The filter_complex command is similar to the desktop Java version.
        // It scales videos to a common height and stacks them horizontally, then merges audio.
        String ffmpegCommand = String.format(
                "-i \"%s\" -i \"%s\" -filter_complex " +
                        "\"[0:v]scale=iw*min(ih\\/ih,ih\\/ih):ih,pad=iw*min(ih\\/ih,ih\\/ih):ih:(ow-iw)/2:(oh-ih)/2[v0];" +
                        "[1:v]scale=iw*min(ih\\/ih,ih\\/ih):ih,pad=iw*min(ih\\/ih,ih\\/ih):ih:(ow-iw)/2:(oh-ih)/2[v1];" +
                        "[v0][v1]hstack=inputs=2[v];" +
                        "[0:a][1:a]amerge=inputs=2[a]\" " +
                        "-map \"[v]\" -map \"[a]\" -ac 2 -y \"%s\"",
                video1Path, video2Path, outputPath
        );

        Log.d(TAG, "Executing FFmpeg command: " + ffmpegCommand);

        // Execute the FFmpeg command asynchronously using FFmpeg-Kit
        FFmpegKit.executeAsync(ffmpegCommand, session -> {
            // This callback runs on a background thread by default,
            // so you might need to post results back to the main thread if updating UI.
            ReturnCode returnCode = session.getReturnCode();

            if (ReturnCode.isSuccess(returnCode)) {
                Log.d(TAG, "FFmpeg command executed successfully. Output: " + outputPath);
                if (listener != null) {
                    // Post to main thread if listener updates UI
                    // new Handler(Looper.getMainLooper()).post(() -> listener.onVideoJoinSuccess(outputPath));
                    listener.onVideoJoinSuccess(outputPath);
                }
            } else if (ReturnCode.isCancel(returnCode)) {
                Log.d(TAG, "FFmpeg command cancelled.");
                if (listener != null) {
                    // new Handler(Looper.getMainLooper()).post(() -> listener.onVideoJoinFailure("Operation cancelled."));
                    listener.onVideoJoinFailure("Operation cancelled.");
                }
            } else {
                Log.e(TAG, String.format("FFmpeg command failed with state %s and return code %s.%s",
                        session.getState(), returnCode, session.getFailStackTrace()));
                if (listener != null) {
                    // new Handler(Looper.getMainLooper()).post(() -> listener.onVideoJoinFailure("FFmpeg failed: " + session.getOutput()));
                    listener.onVideoJoinFailure("FFmpeg failed: " + session.getOutput());
                }
            }
        }, log -> {
            // Optional: Handle FFmpeg logs for progress or debugging
            // Log.d(TAG, "FFmpeg Log: " + log.getMessage());
            // You can parse log.getMessage() to extract progress information
            // and call listener.onVideoJoinProgress()
        }, statistics -> {
            // Optional: Handle FFmpeg statistics for progress updates
            // long timeInMilliseconds = statistics.getTime();
            // long totalDuration = statistics.getDuration(); // This might not always be accurate for complex filters
            // if (listener != null) {
            //     new Handler(Looper.getMainLooper()).post(() -> listener.onVideoJoinProgress(timeInMilliseconds, totalDuration));
            // }
        });
    }

    // Example of how you might call this from an Activity or Fragment
    /*
    // Inside your Activity or Fragment:
    private void startVideoJoining() {
        Uri video1Uri = Uri.parse("file:///sdcard/Download/video1.mp4"); // Replace with actual Uri
        Uri video2Uri = Uri.parse("file:///sdcard/Download/video2.mp4"); // Replace with actual Uri
        String outputFileName = "joined_video_android.mp4";

        AndroidVideoJoiner joiner = new AndroidVideoJoiner(this); // 'this' is the Context
        joiner.setOnVideoJoinListener(new OnVideoJoinListener() {
            @Override
            public void onVideoJoinSuccess(String outputPath) {
                // Handle success on the UI thread
                Log.d(TAG, "Video joined successfully: " + outputPath);
                // Show a Toast, update UI, etc.
            }

            @Override
            public void onVideoJoinFailure(String errorMessage) {
                // Handle failure on the UI thread
                Log.e(TAG, "Video joining failed: " + errorMessage);
                // Show an error message
            }

            @Override
            public void onVideoJoinProgress(long time, long duration) {
                // Optional: Update a progress bar
                // Log.d(TAG, "Progress: " + time + " / " + duration);
            }
        });

        joiner.joinVideosSideBySide(video1Uri, video2Uri, outputFileName);
    }
    */
}
