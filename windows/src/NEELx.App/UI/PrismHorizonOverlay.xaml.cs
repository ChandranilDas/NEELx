using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace NEELx.Windows.UI;

public enum PrismVisualState
{
    Scanning,
    BacklitHdr,
    VerifiedUnlock,
    SpoofRejected
}

/// <summary>
/// Bespoke Windows 11 Fluent Prism Core biometric unlock overlay.
/// Features a sculpted Fluent biometric face encircled by dual 3D tilted orbital prism rings
/// and a vertical volumetric depth-scan sweep, converging into a luminous emerald circle + tick
/// on verified unlock or a damped coral-amber circle + cross on 2D spoof rejection.
/// </summary>
public partial class PrismHorizonOverlay : Window
{
    private readonly Storyboard _scanLoopStoryboard;
    private readonly Storyboard _recoilStoryboard;

    public PrismHorizonOverlay()
    {
        InitializeComponent();
        PositionTopCenter();
        _scanLoopStoryboard = BuildScanLoopStoryboard();
        _recoilStoryboard = BuildRecoilStoryboard();
        Loaded += (_, _) => SetVisualState(PrismVisualState.Scanning);
    }

    private void PositionTopCenter()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Left + (workArea.Width - Width) / 2.0;
        Top = workArea.Top + 18;
    }

    private Storyboard BuildScanLoopStoryboard()
    {
        var sb = new Storyboard { RepeatBehavior = RepeatBehavior.Forever };

        var rotA = new DoubleAnimation(0, 360, TimeSpan.FromSeconds(4.2));
        Storyboard.SetTarget(rotA, OrbitRingA);
        Storyboard.SetTargetProperty(rotA, new PropertyPath("(UIElement.RenderTransform).(TransformGroup.Children)[1].(RotateTransform.Angle)"));
        sb.Children.Add(rotA);

        var rotB = new DoubleAnimation(360, 0, TimeSpan.FromSeconds(3.4));
        Storyboard.SetTarget(rotB, OrbitRingB);
        Storyboard.SetTargetProperty(rotB, new PropertyPath("(UIElement.RenderTransform).(TransformGroup.Children)[1].(RotateTransform.Angle)"));
        sb.Children.Add(rotB);

        var scanSweep = new DoubleAnimation(38, 94, TimeSpan.FromSeconds(1.6))
        {
            AutoReverse = true,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        };
        Storyboard.SetTarget(scanSweep, FaceScanBeam);
        Storyboard.SetTargetProperty(scanSweep, new PropertyPath("(Canvas.Top)"));
        sb.Children.Add(scanSweep);

        return sb;
    }

    private Storyboard BuildRecoilStoryboard()
    {
        var sb = new Storyboard();
        var shake = new DoubleAnimationUsingKeyFrames();
        shake.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(0))));
        shake.KeyFrames.Add(new EasingDoubleKeyFrame(-10, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(65))));
        shake.KeyFrames.Add(new EasingDoubleKeyFrame(9, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(130))));
        shake.KeyFrames.Add(new EasingDoubleKeyFrame(-6, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(195))));
        shake.KeyFrames.Add(new EasingDoubleKeyFrame(3, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(260))));
        shake.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(320))));

        Storyboard.SetTarget(shake, CardShakeTransform);
        Storyboard.SetTargetProperty(shake, new PropertyPath(TranslateTransform.XProperty));
        sb.Children.Add(shake);
        return sb;
    }

    public void SetVisualState(PrismVisualState state)
    {
        switch (state)
        {
            case PrismVisualState.Scanning:
                ApplyPalette(
                    accent: Color.FromRgb(56, 189, 248),
                    secondary: Color.FromRgb(129, 140, 248),
                    title: "PRISM 3D · SCANNING",
                    subtitle: "DirectML GPU · Multi-frame depth");
                FluentFaceGroup.Opacity = 1.0;
                FaceScanBeam.Opacity = 1.0;
                VerifiedCheckPath.Opacity = 0.0;
                SpoofCrossPath.Opacity = 0.0;
                StatusCircleRing.Opacity = 0.0;
                OrbitRingA.Opacity = 0.92;
                OrbitRingB.Opacity = 0.85;
                _scanLoopStoryboard.Begin(this, isControllable: true);
                break;

            case PrismVisualState.BacklitHdr:
                ApplyPalette(
                    accent: Color.FromRgb(251, 191, 36),
                    secondary: Color.FromRgb(56, 189, 248),
                    title: "BACKLIT · HDR LIFT",
                    subtitle: "Recovering shadowed facial relief");
                FluentFaceGroup.Opacity = 1.0;
                FaceScanBeam.Opacity = 1.0;
                VerifiedCheckPath.Opacity = 0.0;
                SpoofCrossPath.Opacity = 0.0;
                StatusCircleRing.Opacity = 0.0;
                OrbitRingA.Opacity = 0.92;
                OrbitRingB.Opacity = 0.85;
                _scanLoopStoryboard.Begin(this, isControllable: true);
                break;

            case PrismVisualState.VerifiedUnlock:
                _scanLoopStoryboard.Stop(this);
                ApplyPalette(
                    accent: Color.FromRgb(48, 209, 88),
                    secondary: Color.FromRgb(52, 211, 153),
                    title: "UNLOCKED · 3D VERIFIED",
                    subtitle: "DPAPI session authenticated");
                FluentFaceGroup.Opacity = 0.0;
                FaceScanBeam.Opacity = 0.0;
                SpoofCrossPath.Opacity = 0.0;
                OrbitRingA.Opacity = 0.0;
                OrbitRingB.Opacity = 0.0;
                StatusCircleRing.Opacity = 1.0;
                VerifiedCheckPath.Opacity = 1.0;
                break;

            case PrismVisualState.SpoofRejected:
                _scanLoopStoryboard.Stop(this);
                ApplyPalette(
                    accent: Color.FromRgb(251, 113, 133),
                    secondary: Color.FromRgb(245, 158, 11),
                    title: "2D SPOOF BLOCKED",
                    subtitle: "Flat surface · No 3D nose relief");
                FluentFaceGroup.Opacity = 0.0;
                FaceScanBeam.Opacity = 0.0;
                VerifiedCheckPath.Opacity = 0.0;
                OrbitRingA.Opacity = 0.0;
                OrbitRingB.Opacity = 0.0;
                StatusCircleRing.Opacity = 1.0;
                SpoofCrossPath.Opacity = 1.0;
                _recoilStoryboard.Begin(this);
                break;
        }
    }

    private void ApplyPalette(Color accent, Color secondary, string title, string subtitle)
    {
        BladeBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(110, accent.R, accent.G, accent.B));
        AuraCoreStop.Color = accent;
        ScanBeamStop.Color = accent;

        OrbitRingA.Stroke = new SolidColorBrush(Color.FromArgb(225, accent.R, accent.G, accent.B));
        OrbitRingB.Stroke = new SolidColorBrush(Color.FromArgb(205, secondary.R, secondary.G, secondary.B));
        OrbitGlowA.Color = accent;
        OrbitGlowB.Color = secondary;

        StatusCircleRing.Stroke = new SolidColorBrush(accent);
        StatusCircleRing.Fill = new SolidColorBrush(Color.FromArgb(22, accent.R, accent.G, accent.B));
        StatusCircleGlow.Color = accent;
        FaceContourPath.Fill = new SolidColorBrush(Color.FromArgb(22, accent.R, accent.G, accent.B));

        PrimaryStatusText.Text = title;
        PrimaryStatusText.Foreground = new SolidColorBrush(accent);
        SecondaryStatusText.Text = subtitle;
    }
}
