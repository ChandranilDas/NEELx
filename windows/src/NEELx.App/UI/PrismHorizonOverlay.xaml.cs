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
/// Bespoke Windows 11 Fluent Prism Horizon biometric unlock blade.
/// Intentionally distinct from macOS/iOS's circular notch Face ID animation:
/// uses a top-edge dark Mica glass blade, counter-rotating faceted crystalline
/// diamond-iris, and horizontal laser horizon sweep.
/// </summary>
public partial class PrismHorizonOverlay : Window
{
    private readonly Storyboard _scanLoopStoryboard;

    public PrismHorizonOverlay()
    {
        InitializeComponent();
        PositionTopCenter();
        _scanLoopStoryboard = BuildScanLoopStoryboard();
        Loaded += (_, _) => SetVisualState(PrismVisualState.Scanning);
    }

    private void PositionTopCenter()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Left + (workArea.Width - Width) / 2.0;
        Top = workArea.Top + 14;
    }

    private Storyboard BuildScanLoopStoryboard()
    {
        var sb = new Storyboard { RepeatBehavior = RepeatBehavior.Forever };

        var outerSpin = new DoubleAnimation(0, 360, TimeSpan.FromSeconds(5.2));
        Storyboard.SetTarget(outerSpin, OuterPrism);
        Storyboard.SetTargetProperty(outerSpin, new PropertyPath("(UIElement.RenderTransform).(RotateTransform.Angle)"));
        sb.Children.Add(outerSpin);

        var innerSpin = new DoubleAnimation(45, -315, TimeSpan.FromSeconds(3.6));
        Storyboard.SetTarget(innerSpin, InnerPrism);
        Storyboard.SetTargetProperty(innerSpin, new PropertyPath("(UIElement.RenderTransform).(RotateTransform.Angle)"));
        sb.Children.Add(innerSpin);

        var laserSweep = new DoubleAnimation(-140, 420, TimeSpan.FromSeconds(1.45))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        Storyboard.SetTarget(laserSweep, HorizonLaserBeam);
        Storyboard.SetTargetProperty(laserSweep, new PropertyPath("(Canvas.Left)"));
        sb.Children.Add(laserSweep);

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
                    title: "NEELx Prism · Scanning 3D Depth",
                    subtitle: "DirectML GPU · Multi-frame geometry verification",
                    pillText: "PRISM 3D");
                _scanLoopStoryboard.Begin(this, isControllable: true);
                break;

            case PrismVisualState.BacklitHdr:
                ApplyPalette(
                    accent: Color.FromRgb(251, 191, 36),
                    secondary: Color.FromRgb(56, 189, 248),
                    title: "Backlit Silhouette · HDR Shadow Lift",
                    subtitle: "Recovering facial relief against bright window",
                    pillText: "HDR LIFT");
                _scanLoopStoryboard.Begin(this, isControllable: true);
                break;

            case PrismVisualState.VerifiedUnlock:
                _scanLoopStoryboard.Stop(this);
                OuterPrismRotate.Angle = 0;
                InnerPrismRotate.Angle = 0;
                ApplyPalette(
                    accent: Color.FromRgb(48, 209, 88),
                    secondary: Color.FromRgb(52, 211, 153),
                    title: "Identity & 3D Depth Verified",
                    subtitle: "DPAPI session unlocked · 2 frames confirmed",
                    pillText: "UNLOCKED");
                break;

            case PrismVisualState.SpoofRejected:
                _scanLoopStoryboard.Stop(this);
                ApplyPalette(
                    accent: Color.FromRgb(251, 113, 133),
                    secondary: Color.FromRgb(245, 158, 11),
                    title: "Flat 2D Surface Rejected",
                    subtitle: "Insufficient nose protrusion & background cliff",
                    pillText: "BLOCKED");
                break;
        }
    }

    private void ApplyPalette(Color accent, Color secondary, string title, string subtitle, string pillText)
    {
        BladeBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(95, accent.R, accent.G, accent.B));
        TopRimStopA.Color = accent;
        TopRimStopB.Color = secondary;
        LaserCoreStop.Color = accent;

        OuterPrism.Stroke = new SolidColorBrush(Color.FromArgb(225, accent.R, accent.G, accent.B));
        OuterPrism.Fill = new SolidColorBrush(Color.FromArgb(30, accent.R, accent.G, accent.B));
        InnerPrism.Stroke = new SolidColorBrush(Color.FromArgb(220, secondary.R, secondary.G, secondary.B));
        InnerPrism.Fill = new SolidColorBrush(Color.FromArgb(40, secondary.R, secondary.G, secondary.B));
        CoreDiamond.Fill = new SolidColorBrush(accent);

        PrimaryStatusText.Text = title;
        SecondaryStatusText.Text = subtitle;
        StatusPillText.Text = pillText;
        StatusPillText.Foreground = new SolidColorBrush(accent);
        StatusPill.Background = new SolidColorBrush(Color.FromArgb(32, accent.R, accent.G, accent.B));
        StatusPill.BorderBrush = new SolidColorBrush(Color.FromArgb(90, accent.R, accent.G, accent.B));
    }
}
