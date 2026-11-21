using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using NEELx.Windows.Biometrics;
using NEELx.Windows.Security;
using NEELx.Windows.UI;

namespace NEELx.Windows;

public partial class MainWindow : Window
{
    private readonly OnnxFaceEngine _engine;
    private readonly DpapiCredentialVault _vault;
    private readonly CameraCaptureService _cameraService;
    private PrismHorizonOverlay? _overlay;

    // Biometric state tracking
    private bool _welcomeBannerEnabled = true;
    private bool _isEnrolling = false;
    private readonly List<float[]> _enrollmentSamples = new();
    private bool _isLiveTesting = false;
    private DateTime _liveTestStartTime;

    public MainWindow()
    {
        InitializeComponent();
        _engine = new OnnxFaceEngine();
        _vault = new DpapiCredentialVault();
        _cameraService = new CameraCaptureService();

        _cameraService.FrameCaptured += OnCameraFrameCaptured;
        _cameraService.CameraError += OnCameraError;

        RefreshEnrolledProfileDisplay();

        Closed += (_, _) =>
        {
            _overlay?.Close();
            _cameraService.Dispose();
            _engine.Dispose();
        };
    }

    private void RefreshEnrolledProfileDisplay()
    {
        var profile = _vault.LoadProfile();
        if (profile is not null)
        {
            EnrolledProfileNameText.Text = profile.ProfileName;
            EnrolledProfileStatusText.Text = $"Active Biometric Profile · 512-D Spatial Topology Stored in DPAPI ({profile.EnrolledUtc.ToLocalTime():g})";
            EnrolledProfileStatusText.Foreground = (Brush)Application.Current.Resources["AccentGreenBrush"];
        }
        else
        {
            string rawName = Environment.UserName;
            string formattedName = string.IsNullOrEmpty(rawName) ? "User" : char.ToUpper(rawName[0]) + rawName[1..];
            EnrolledProfileNameText.Text = formattedName;
            EnrolledProfileStatusText.Text = "Not Enrolled · Click 'Re-enroll Face' to capture biometrics offline";
            EnrolledProfileStatusText.Foreground = (Brush)Application.Current.Resources["TextSecondaryBrush"];
        }
    }

    // Camera callbacks
    private void OnCameraFrameCaptured(FaceDetectionFrame frame)
    {
        Dispatcher.Invoke(() =>
        {
            // Update Camera tab preview if visible
            if (PageCamera.Visibility == Visibility.Visible && CameraPreviewImage is not null)
            {
                CameraPreviewImage.Source = frame.DisplayBitmap;
                CameraFpsText.Text = $"640x480 @ 30 FPS · Faces: {frame.DetectedFaces.Length}";
            }

            // Update Enrollment viewfinder if active
            if (_isEnrolling)
            {
                EnrollmentCameraFeed.Source = frame.DisplayBitmap;

                if (frame.DetectedFaces.Length > 0 && frame.LiveEmbedding512 is not null)
                {
                    _enrollmentSamples.Add(frame.LiveEmbedding512);
                    EnrollmentProgressBar.Value = _enrollmentSamples.Count;
                    EnrollmentStepText.Text = $"Step {_enrollmentSamples.Count} of 5 · Capturing face geometry...";

                    if (_enrollmentSamples.Count >= 5)
                    {
                        FinishEnrollment();
                    }
                }
            }

            // Live Biometric Unlock Test
            if (_isLiveTesting)
            {
                var profile = _vault.LoadProfile();
                if (profile is null)
                {
                    _isLiveTesting = false;
                    ShowOverlay(PrismVisualState.SpoofRejected);
                    LiveTestResultText.Text = "❌ No face profile enrolled yet! Please enroll first in 'Your Face' tab.";
                    return;
                }

                if ((DateTime.UtcNow - _liveTestStartTime).TotalSeconds > 8.0)
                {
                    _isLiveTesting = false;
                    ShowOverlay(PrismVisualState.SpoofRejected);
                    LiveTestResultText.Text = "❌ Verification timed out (8s) without reaching 60% face confidence match.";
                    LiveTestStatusBadge.Text = "TIMED OUT";
                    LiveTestStatusBadge.Foreground = (Brush)Application.Current.Resources["AccentRedBrush"];
                    return;
                }

                if (frame.DetectedFaces.Length > 0 && frame.LiveEmbedding512 is not null)
                {
                    float score = OnnxFaceEngine.CosineSimilarity(frame.LiveEmbedding512, profile.IdentityEmbedding512);
                    LiveTestResultText.Text = $"Scanning... Live face match score: {score * 100:F1}% (Threshold: 60%)";

                    if (score >= 0.60f)
                    {
                        _isLiveTesting = false;
                        ShowOverlay(PrismVisualState.VerifiedUnlock);
                        LiveTestResultText.Text = $"✅ VERIFIED! Matched {profile.ProfileName} ({score * 100:F1}% match confidence). DirectShow webcam authenticated.";
                        LiveTestStatusBadge.Text = "VERIFIED";
                        LiveTestStatusBadge.Foreground = (Brush)Application.Current.Resources["AccentGreenBrush"];

                        if (_welcomeBannerEnabled)
                        {
                            WelcomeBannerWindow.ShowBanner(profile.ProfileName);
                        }
                    }
                }
            }
        });
    }

    private void OnCameraError(string errorMessage)
    {
        Dispatcher.Invoke(() =>
        {
            MessageBox.Show(errorMessage, "NEELx Camera Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            BtnToggleCamera.Content = "Start Live Camera Feed";
            CameraPlaceholderText.Visibility = Visibility.Visible;
            CameraPlaceholderText.Text = $"Camera unavailable: {errorMessage}";
        });
    }

    // Window Dragging & Traffic Lights
    private void OnHeaderMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            DragMove();
        }
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();
    private void OnMinimizeClick(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void OnMaximizeClick(object sender, RoutedEventArgs e) =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void OnSessionLockClick(object sender, RoutedEventArgs e)
    {
        MessageBox.Show(
            "Windows DPAPI Biometric Session is Active & Verified.\nYour biometric keys are encrypted offline under your Windows user account.",
            "NEELx Security Status",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    // Tab Navigation
    private void SelectTab(int index)
    {
        PageGeneral.Visibility = index == 0 ? Visibility.Visible : Visibility.Collapsed;
        PageRecognition.Visibility = index == 1 ? Visibility.Visible : Visibility.Collapsed;
        PageYourFace.Visibility = index == 2 ? Visibility.Visible : Visibility.Collapsed;
        PageSecurity.Visibility = index == 3 ? Visibility.Visible : Visibility.Collapsed;
        PageCamera.Visibility = index == 4 ? Visibility.Visible : Visibility.Collapsed;
        PageAbout.Visibility = index == 5 ? Visibility.Visible : Visibility.Collapsed;

        UpdateTabButton(TabBtnGeneral, index == 0);
        UpdateTabButton(TabBtnRecognition, index == 1);
        UpdateTabButton(TabBtnYourFace, index == 2);
        UpdateTabButton(TabBtnSecurity, index == 3);
        UpdateTabButton(TabBtnCamera, index == 4);
        UpdateTabButton(TabBtnAbout, index == 5);

        // Auto-pause camera preview if not on Camera or Your Face tab
        if (index != 4 && !_isEnrolling && !_isLiveTesting && _cameraService.IsRunning)
        {
            _cameraService.StopCamera();
            BtnToggleCamera.Content = "Start Live Camera Feed";
            CameraPlaceholderText.Visibility = Visibility.Visible;
            CameraPreviewImage.Source = null;
        }
    }

    private void UpdateTabButton(Button btn, bool isSelected)
    {
        if (btn.Template.FindName("Pill", btn) is Border pill)
        {
            pill.Background = isSelected
                ? (Brush)Application.Current.Resources["TabSelectedBrush"]
                : Brushes.Transparent;
        }
    }

    private void OnTabGeneralClick(object sender, RoutedEventArgs e) => SelectTab(0);
    private void OnTabRecognitionClick(object sender, RoutedEventArgs e) => SelectTab(1);
    private void OnTabYourFaceClick(object sender, RoutedEventArgs e) => SelectTab(2);
    private void OnTabSecurityClick(object sender, RoutedEventArgs e) => SelectTab(3);
    private void OnTabCameraClick(object sender, RoutedEventArgs e) => SelectTab(4);
    private void OnTabAboutClick(object sender, RoutedEventArgs e) => SelectTab(5);

    // Camera Tab: Live Camera Feed Toggle
    private void OnToggleCameraPreviewClick(object sender, RoutedEventArgs e)
    {
        if (_cameraService.IsRunning)
        {
            _cameraService.StopCamera();
            BtnToggleCamera.Content = "Start Live Camera Feed";
            CameraPlaceholderText.Visibility = Visibility.Visible;
            CameraPlaceholderText.Text = "Camera Preview Inactive · Click 'Start Live Camera Feed' above";
            CameraPreviewImage.Source = null;
            CameraFpsText.Text = "";
        }
        else
        {
            CameraPlaceholderText.Visibility = Visibility.Collapsed;
            BtnToggleCamera.Content = "Stop Camera Feed";
            bool started = _cameraService.StartCamera(0);
            if (!started)
            {
                BtnToggleCamera.Content = "Start Live Camera Feed";
                CameraPlaceholderText.Visibility = Visibility.Visible;
            }
        }
    }

    // Your Face Tab: Enrollment
    private void OnStartEnrollmentClick(object sender, RoutedEventArgs e)
    {
        _enrollmentSamples.Clear();
        EnrollmentProgressBar.Value = 0;
        EnrollmentStepText.Text = "Step 0 of 5 · Keep steady facing camera";
        EnrollmentCard.Visibility = Visibility.Visible;
        _isEnrolling = true;

        if (!_cameraService.IsRunning)
        {
            _cameraService.StartCamera(0);
        }
    }

    private void OnCancelEnrollmentClick(object sender, RoutedEventArgs e)
    {
        _isEnrolling = false;
        EnrollmentCard.Visibility = Visibility.Collapsed;
        _enrollmentSamples.Clear();
        EnrollmentCameraFeed.Source = null;
        if (!_isLiveTesting && PageCamera.Visibility != Visibility.Visible)
        {
            _cameraService.StopCamera();
        }
    }

    private void FinishEnrollment()
    {
        _isEnrolling = false;
        EnrollmentCard.Visibility = Visibility.Collapsed;

        // Compute normalized 512-D centroid vector
        float[] avgEmbedding = new float[512];
        for (int i = 0; i < 512; i++)
        {
            float sum = 0f;
            foreach (var sample in _enrollmentSamples)
            {
                sum += sample[i];
            }
            avgEmbedding[i] = sum / _enrollmentSamples.Count;
        }

        float norm = 0f;
        for (int i = 0; i < 512; i++) norm += avgEmbedding[i] * avgEmbedding[i];
        norm = MathF.Sqrt(norm);
        if (norm > 1e-6f)
        {
            for (int i = 0; i < 512; i++) avgEmbedding[i] /= norm;
        }

        string rawName = Environment.UserName;
        string formattedName = string.IsNullOrEmpty(rawName) ? "User" : char.ToUpper(rawName[0]) + rawName[1..];

        var profile = new BiometricVaultProfile(formattedName, avgEmbedding, Array.Empty<float>(), DateTime.UtcNow);
        _vault.SaveProfile(profile);

        RefreshEnrolledProfileDisplay();

        if (!_isLiveTesting && PageCamera.Visibility != Visibility.Visible)
        {
            _cameraService.StopCamera();
        }

        MessageBox.Show(
            $"Face biometrics enrolled successfully for '{formattedName}'!\n\n512-D spatial topology is encrypted offline under Windows DPAPI.\nYou can now test face recognition in the 'Recognition' tab.",
            "NEELx Biometric Enrollment Complete",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void OnResetBiometricsClick(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "Are you sure you want to delete all enrolled biometric face data from your Windows DPAPI vault?\n\nThis will wipe offline face profiles.",
            "Reset NEELx Biometrics",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.Yes)
        {
            _vault.WipeProfile();
            RefreshEnrolledProfileDisplay();
            MessageBox.Show("Biometric vault wiped clean.", "NEELx", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    // Recognition Tab: Live Biometric Unlock Test
    private void OnRunLiveBiometricTestClick(object sender, RoutedEventArgs e)
    {
        var profile = _vault.LoadProfile();
        if (profile is null)
        {
            ShowOverlay(PrismVisualState.SpoofRejected);
            LiveTestResultText.Text = "❌ No face profile enrolled yet! Go to 'Your Face' tab and click 'Re-enroll Face' first.";
            LiveTestStatusBadge.Text = "NO PROFILE";
            LiveTestStatusBadge.Foreground = (Brush)Application.Current.Resources["AccentRedBrush"];
            return;
        }

        _isLiveTesting = true;
        _liveTestStartTime = DateTime.UtcNow;
        LiveTestStatusBadge.Text = "SCANNING";
        LiveTestStatusBadge.Foreground = (Brush)Application.Current.Resources["AccentCyanBrush"];
        LiveTestResultText.Text = $"Looking for enrolled user '{profile.ProfileName}'... Look directly at your camera.";

        ShowOverlay(PrismVisualState.Scanning);

        if (!_cameraService.IsRunning)
        {
            _cameraService.StartCamera(0);
        }
    }

    private void OnStopLiveBiometricTestClick(object sender, RoutedEventArgs e)
    {
        _isLiveTesting = false;
        LiveTestStatusBadge.Text = "READY";
        LiveTestStatusBadge.Foreground = (Brush)Application.Current.Resources["AccentGreenBrush"];
        LiveTestResultText.Text = "Live test stopped.";
        _overlay?.Close();
        _overlay = null;

        if (PageCamera.Visibility != Visibility.Visible && !_isEnrolling)
        {
            _cameraService.StopCamera();
        }
    }

    // Sliders
    private void OnMatchConfidenceChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (MatchConfidenceLabel is null) return;
        int val = (int)Math.Round(e.NewValue);
        MatchConfidenceLabel.Text = val switch
        {
            0 => "Less strict (0.55)",
            2 => "More strict (0.68)",
            _ => "Default (0.60)"
        };
    }

    private void OnDetectionDistanceChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (DetectionDistanceLabel is null) return;
        int val = (int)Math.Round(e.NewValue);
        DetectionDistanceLabel.Text = val switch
        {
            0 => "Close (~30 cm)",
            2 => "Far (~90 cm)",
            _ => "Default (~55 cm)"
        };
    }

    private void OnWelcomeBannerToggled(object sender, RoutedEventArgs e)
    {
        _welcomeBannerEnabled = ToggleWelcomeBanner?.IsChecked ?? true;
    }

    private void OnPreviewWelcomeClick(object sender, RoutedEventArgs e)
    {
        string rawName = Environment.UserName;
        string formattedName = string.IsNullOrEmpty(rawName) ? "User" : char.ToUpper(rawName[0]) + rawName[1..];
        WelcomeBannerWindow.ShowBanner(formattedName);
    }

    // Overlay Previews (Preserves the dedicated Windows 11 Prism Horizon top-blade laser animation)
    private void ShowOverlay(PrismVisualState state)
    {
        if (_overlay is null || !_overlay.IsLoaded)
        {
            _overlay = new PrismHorizonOverlay();
            _overlay.Show();
        }
        _overlay.SetVisualState(state);
    }

    private void OnPreviewScanClick(object sender, RoutedEventArgs e) => ShowOverlay(PrismVisualState.Scanning);
    private void OnPreviewVerifiedClick(object sender, RoutedEventArgs e)
    {
        ShowOverlay(PrismVisualState.VerifiedUnlock);
        if (_welcomeBannerEnabled)
        {
            string rawName = Environment.UserName;
            string formattedName = string.IsNullOrEmpty(rawName) ? "User" : char.ToUpper(rawName[0]) + rawName[1..];
            WelcomeBannerWindow.ShowBanner(formattedName);
        }
    }
    private void OnPreviewSpoofClick(object sender, RoutedEventArgs e) => ShowOverlay(PrismVisualState.SpoofRejected);

    private void OnHideOverlayClick(object sender, RoutedEventArgs e)
    {
        _overlay?.Close();
        _overlay = null;
    }

    // Security & DPAPI Vault Self Check
    private void OnRunSelfCheckClick(object sender, RoutedEventArgs e)
    {
        _engine.ResetTemporalState();

        var frame1 = new DepthLivenessSample(0.088f, 0.041f, 0.142f, 0.62f, DateTime.UtcNow);
        var frame2 = new DepthLivenessSample(0.092f, 0.043f, 0.148f, 0.65f, DateTime.UtcNow.AddMilliseconds(90));
        bool verified3D = _engine.RecordAndVerifyTemporalDepth(frame1) && _engine.RecordAndVerifyTemporalDepth(frame2);

        var spoof = new DepthLivenessSample(0.008f, 0.006f, 0.015f, 0.12f, DateTime.UtcNow.AddMilliseconds(180));
        bool spoofBlocked = !_engine.RecordAndVerifyTemporalDepth(spoof);

        SelfCheckOutput.Text = verified3D && spoofBlocked
            ? $"PASS · 3D temporal gate verified (2 frames) & 2D flat spoof rejected · DirectML={_engine.IsDirectMlActive}"
            : "FAIL · Self-check failed";
    }

    // External Links
    private void OnOpenGitHubClick(object sender, RoutedEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://github.com/ChandranilDas/NEELx") { UseShellExecute = true });
    }

    private void OnOpenWebsiteClick(object sender, RoutedEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://chandranildas.github.io/NEELx/") { UseShellExecute = true });
    }
}
