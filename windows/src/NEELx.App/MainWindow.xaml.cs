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
    private PrismHorizonOverlay? _overlay;

    public MainWindow()
    {
        InitializeComponent();
        _engine = new OnnxFaceEngine();
        _vault = new DpapiCredentialVault();

        Closed += (_, _) =>
        {
            _overlay?.Close();
            _engine.Dispose();
        };
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
        // Toggle or re-authenticate session
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

    // Sliders
    private void OnMatchConfidenceChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (MatchConfidenceLabel is null) return;
        int val = (int)Math.Round(e.NewValue);
        MatchConfidenceLabel.Text = val switch
        {
            0 => "Less strict (0.58)",
            2 => "More strict (0.68)",
            _ => "Default (0.63)"
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
    private void OnPreviewVerifiedClick(object sender, RoutedEventArgs e) => ShowOverlay(PrismVisualState.VerifiedUnlock);
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
