using System.Windows;
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

        AcceleratorBadge.Text = _engine.IsDirectMlActive
            ? "DirectML GPU/NPU Active"
            : "ONNX CPU Mode";

        VaultStatusText.Text = _vault.HasEnrolledProfile
            ? "Enrolled 3D DPAPI biometric profile present in %LOCALAPPDATA%\\NEELx."
            : "No profile enrolled yet. Place ArcFace + DepthAnythingV2Small ONNX models in %LOCALAPPDATA%\\NEELx\\models to enroll.";

        Closed += (_, _) =>
        {
            _overlay?.Close();
            _engine.Dispose();
        };
    }

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
    private void OnPreviewBacklitClick(object sender, RoutedEventArgs e) => ShowOverlay(PrismVisualState.BacklitHdr);
    private void OnPreviewVerifiedClick(object sender, RoutedEventArgs e) => ShowOverlay(PrismVisualState.VerifiedUnlock);
    private void OnPreviewSpoofClick(object sender, RoutedEventArgs e) => ShowOverlay(PrismVisualState.SpoofRejected);

    private void OnHideOverlayClick(object sender, RoutedEventArgs e)
    {
        _overlay?.Close();
        _overlay = null;
    }

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
}
