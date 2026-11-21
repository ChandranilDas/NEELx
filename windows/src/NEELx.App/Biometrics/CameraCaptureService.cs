using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;
using OpenCvSharp;
using OpenCvSharp.WpfExtensions;
using CvRect = OpenCvSharp.Rect;
using CvSize = OpenCvSharp.Size;
using CvPoint = OpenCvSharp.Point;
using CvScalar = OpenCvSharp.Scalar;

namespace NEELx.Windows.Biometrics;

public sealed record FaceDetectionFrame(
    BitmapSource DisplayBitmap,
    CvRect[] DetectedFaces,
    float[]? LiveEmbedding512);

/// <summary>
/// High-performance camera capture and face detection service for Windows 11.
/// Uses OpenCV for DirectShow webcam access and Haar Cascade face tracking,
/// with normalized 512-D spatial feature extraction for offline DPAPI matching.
/// </summary>
public sealed class CameraCaptureService : IDisposable
{
    private VideoCapture? _capture;
    private CascadeClassifier? _faceCascade;
    private CancellationTokenSource? _captureCts;
    private Task? _captureTask;
    private readonly object _lock = new();

    public bool IsRunning => _captureCts is not null && !_captureCts.IsCancellationRequested;
    public event Action<FaceDetectionFrame>? FrameCaptured;
    public event Action<string>? CameraError;

    public CameraCaptureService()
    {
        InitializeCascade();
    }

    private void InitializeCascade()
    {
        try
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] possiblePaths =
            [
                Path.Combine(baseDir, "Assets", "haarcascade_frontalface_default.xml"),
                Path.Combine(baseDir, "haarcascade_frontalface_default.xml"),
                Path.Combine(Directory.GetCurrentDirectory(), "Assets", "haarcascade_frontalface_default.xml"),
                Path.Combine(Directory.GetCurrentDirectory(), "windows", "src", "NEELx.App", "Assets", "haarcascade_frontalface_default.xml")
            ];

            foreach (var p in possiblePaths)
            {
                if (File.Exists(p))
                {
                    _faceCascade = new CascadeClassifier(p);
                    if (!_faceCascade.Empty())
                    {
                        return;
                    }
                }
            }
        }
        catch
        {
            // Cascade load failure handled gracefully below
        }
    }

    public bool StartCamera(int cameraIndex = 0)
    {
        lock (_lock)
        {
            if (IsRunning) return true;

            try
            {
                // Try DirectShow first on Windows, fallback to default
                _capture = new VideoCapture(cameraIndex, VideoCaptureAPIs.DSHOW);
                if (!_capture.IsOpened())
                {
                    _capture.Dispose();
                    _capture = new VideoCapture(cameraIndex);
                }

                if (!_capture.IsOpened())
                {
                    CameraError?.Invoke($"Unable to open camera {cameraIndex}. Verify webcam connection and privacy permissions.");
                    return false;
                }

                _capture.Set(VideoCaptureProperties.FrameWidth, 640);
                _capture.Set(VideoCaptureProperties.FrameHeight, 480);
                _capture.Set(VideoCaptureProperties.Fps, 30);

                _captureCts = new CancellationTokenSource();
                var token = _captureCts.Token;
                _captureTask = Task.Run(() => CaptureLoop(token), token);
                return true;
            }
            catch (Exception ex)
            {
                CameraError?.Invoke($"Camera initialization error: {ex.Message}");
                return false;
            }
        }
    }

    public void StopCamera()
    {
        lock (_lock)
        {
            if (_captureCts is not null)
            {
                _captureCts.Cancel();
                try
                {
                    _captureTask?.Wait(500);
                }
                catch { }
                _captureCts.Dispose();
                _captureCts = null;
            }

            if (_capture is not null)
            {
                _capture.Release();
                _capture.Dispose();
                _capture = null;
            }
        }
    }

    private void CaptureLoop(CancellationToken token)
    {
        using var frame = new Mat();
        using var gray = new Mat();

        while (!token.IsCancellationRequested)
        {
            if (_capture is null || !_capture.IsOpened())
            {
                break;
            }

            bool readSuccess = _capture.Read(frame);
            if (!readSuccess || frame.Empty())
            {
                Thread.Sleep(15);
                continue;
            }

            // Detect faces
            CvRect[] detectedFaces = Array.Empty<CvRect>();
            float[]? embedding = null;

            if (_faceCascade is not null && !_faceCascade.Empty())
            {
                Cv2.CvtColor(frame, gray, ColorConversionCodes.BGR2GRAY);
                Cv2.EqualizeHist(gray, gray);

                detectedFaces = _faceCascade.DetectMultiScale(
                    gray,
                    scaleFactor: 1.15,
                    minNeighbors: 4,
                    minSize: new CvSize(70, 70));

                if (detectedFaces.Length > 0)
                {
                    // Draw target HUD corners on primary face
                    var primaryFace = detectedFaces[0];
                    DrawFaceTrackingHud(frame, primaryFace);

                    // Extract 512-D feature vector from face region
                    using var faceMat = new Mat(gray, primaryFace);
                    embedding = ExtractSpatialEmbedding512(faceMat);
                }
            }

            try
            {
                // Convert Mat to WPF BitmapSource for zero-copy UI rendering
                var bitmap = frame.ToBitmapSource();
                bitmap.Freeze();

                FrameCaptured?.Invoke(new FaceDetectionFrame(bitmap, detectedFaces, embedding));
            }
            catch
            {
                // Disposed or UI shutdown
            }

            // 30 FPS throttle
            Thread.Sleep(20);
        }
    }

    private static void DrawFaceTrackingHud(Mat img, CvRect face)
    {
        // Fluent Neon Cyan (#38BDF8 -> BGR: 248, 189, 56)
        var color = new CvScalar(248, 189, 56);
        int cornerLen = Math.Min(face.Width, face.Height) / 5;
        int thickness = 2;

        // Top-Left
        Cv2.Line(img, new CvPoint(face.Left, face.Top), new CvPoint(face.Left + cornerLen, face.Top), color, thickness);
        Cv2.Line(img, new CvPoint(face.Left, face.Top), new CvPoint(face.Left, face.Top + cornerLen), color, thickness);

        // Top-Right
        Cv2.Line(img, new CvPoint(face.Right, face.Top), new CvPoint(face.Right - cornerLen, face.Top), color, thickness);
        Cv2.Line(img, new CvPoint(face.Right, face.Top), new CvPoint(face.Right, face.Top + cornerLen), color, thickness);

        // Bottom-Left
        Cv2.Line(img, new CvPoint(face.Left, face.Bottom), new CvPoint(face.Left + cornerLen, face.Bottom), color, thickness);
        Cv2.Line(img, new CvPoint(face.Left, face.Bottom), new CvPoint(face.Left, face.Bottom - cornerLen), color, thickness);

        // Bottom-Right
        Cv2.Line(img, new CvPoint(face.Right, face.Bottom), new CvPoint(face.Right - cornerLen, face.Bottom), color, thickness);
        Cv2.Line(img, new CvPoint(face.Right, face.Bottom), new CvPoint(face.Right, face.Bottom - cornerLen), color, thickness);

        // Status text overlay
        Cv2.PutText(img, "NEELx Face Lock", new CvPoint(face.Left, Math.Max(20, face.Top - 8)),
            HersheyFonts.HersheySimplex, 0.45, color, 1, LineTypes.AntiAlias);
    }

    /// <summary>
    /// Computes a normalized 512-dimensional spatial gradient and multi-zone descriptor
    /// from an aligned 112x112 face crop. L2-normalized so dot(a, b) == cosine similarity.
    /// </summary>
    public static float[] ExtractSpatialEmbedding512(Mat grayFace)
    {
        using var resized = new Mat();
        Cv2.Resize(grayFace, resized, new CvSize(112, 112));

        float[] vector = new float[512];
        int writeIdx = 0;

        // Part 1: 8x8 Block Luminance Means & StdDevs (64 + 64 = 128 dimensions)
        for (int r = 0; r < 8; r++)
        {
            for (int c = 0; c < 8; c++)
            {
                var blockRect = new CvRect(c * 14, r * 14, 14, 14);
                using var block = new Mat(resized, blockRect);
                Cv2.MeanStdDev(block, out var mean, out var stddev);
                vector[writeIdx++] = (float)(mean.Val0 / 255.0);
                vector[writeIdx++] = (float)(stddev.Val0 / 128.0);
            }
        }

        // Part 2: Sobel Horizontal & Vertical Edge Energy in 64 cells (64 + 64 = 128 dimensions)
        using var sobelX = new Mat();
        using var sobelY = new Mat();
        Cv2.Sobel(resized, sobelX, MatType.CV_32F, 1, 0, 3);
        Cv2.Sobel(resized, sobelY, MatType.CV_32F, 0, 1, 3);
        using var absX = new Mat();
        using var absY = new Mat();
        Cv2.ConvertScaleAbs(sobelX, absX);
        Cv2.ConvertScaleAbs(sobelY, absY);

        for (int r = 0; r < 8; r++)
        {
            for (int c = 0; c < 8; c++)
            {
                var blockRect = new CvRect(c * 14, r * 14, 14, 14);
                using var bX = new Mat(absX, blockRect);
                using var bY = new Mat(absY, blockRect);
                vector[writeIdx++] = (float)(Cv2.Mean(bX).Val0 / 255.0);
                vector[writeIdx++] = (float)(Cv2.Mean(bY).Val0 / 255.0);
            }
        }

        // Part 3: Radial Profile & Concentric Symmetry (128 dimensions)
        int cx = 56, cy = 56;
        for (int band = 0; band < 16; band++)
        {
            double rMin = band * 3.5;
            double rMax = (band + 1) * 3.5;
            double[] sectorSums = new double[8];
            int[] sectorCounts = new int[8];

            for (int y = 0; y < 112; y += 2)
            {
                for (int x = 0; x < 112; x += 2)
                {
                    double dx = x - cx;
                    double dy = y - cy;
                    double dist = Math.Sqrt(dx * dx + dy * dy);
                    if (dist >= rMin && dist < rMax)
                    {
                        double angle = Math.Atan2(dy, dx) + Math.PI; // 0 .. 2PI
                        int sector = Math.Clamp((int)(angle / (2.0 * Math.PI) * 8.0), 0, 7);
                        sectorSums[sector] += resized.At<byte>(y, x);
                        sectorCounts[sector]++;
                    }
                }
            }

            for (int s = 0; s < 8; s++)
            {
                vector[writeIdx++] = sectorCounts[s] > 0
                    ? (float)(sectorSums[s] / (sectorCounts[s] * 255.0))
                    : 0f;
            }
        }

        // Part 4: Central T-Zone (Eyes & Nose Bridge) Fine Detail (128 dimensions)
        // Subdivide center 56x56 into 4x4 fine blocks, 8 gradient angle histogram bins
        for (int br = 0; br < 4; br++)
        {
            for (int bc = 0; bc < 4; bc++)
            {
                var fineRect = new CvRect(28 + bc * 14, 28 + br * 14, 14, 14);
                using var fineMat = new Mat(resized, fineRect);
                using var fSobelX = new Mat(sobelX, fineRect);
                using var fSobelY = new Mat(sobelY, fineRect);

                float[] hist = new float[8];
                for (int y = 0; y < 14; y++)
                {
                    for (int x = 0; x < 14; x++)
                    {
                        float gx = fSobelX.At<float>(y, x);
                        float gy = fSobelY.At<float>(y, x);
                        float mag = MathF.Sqrt(gx * gx + gy * gy);
                        float ang = MathF.Atan2(gy, gx) + MathF.PI;
                        int bin = Math.Clamp((int)(ang / (2.0f * MathF.PI) * 8.0f), 0, 7);
                        hist[bin] += mag;
                    }
                }

                float histSum = 0f;
                for (int b = 0; b < 8; b++) histSum += hist[b];
                for (int b = 0; b < 8; b++)
                {
                    vector[writeIdx++] = histSum > 1e-4f ? hist[b] / histSum : 0f;
                }
            }
        }

        // L2 Normalize full 512-D vector so dot product equals cosine similarity
        float norm = 0f;
        for (int i = 0; i < 512; i++)
        {
            norm += vector[i] * vector[i];
        }
        norm = MathF.Sqrt(norm);
        if (norm > 1e-6f)
        {
            for (int i = 0; i < 512; i++)
            {
                vector[i] /= norm;
            }
        }

        return vector;
    }

    public void Dispose()
    {
        StopCamera();
        _faceCascade?.Dispose();
        _faceCascade = null;
    }
}
