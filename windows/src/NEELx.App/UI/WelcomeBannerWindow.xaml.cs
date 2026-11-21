using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Animation;

namespace NEELx.Windows.UI;

/// <summary>
/// Floating top-edge popup message displayed right after successful face authorization:
/// "Welcome Back (Name)!", sliding in from above and retracting back above.
/// </summary>
public partial class WelcomeBannerWindow : Window
{
    public WelcomeBannerWindow(string name)
    {
        InitializeComponent();
        WelcomeText.Text = $"Welcome Back, {name}!";
        PositionTopCenter();
        Loaded += (_, _) => AnimateBanner();
    }

    private void PositionTopCenter()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Left + (workArea.Width - Width) / 2.0;
        Top = workArea.Top + 14;
    }

    private async void AnimateBanner()
    {
        // 1. Smooth slide down from above (Y: -65 -> 0)
        var slideIn = new DoubleAnimation(-65, 0, TimeSpan.FromMilliseconds(380))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        BannerTranslate.BeginAnimation(TranslateTransform.YProperty, slideIn);

        // 2. Linger for minimal duration (~1.8 seconds)
        await Task.Delay(1800);

        // 3. Smooth slide back up to above (Y: 0 -> -65)
        var slideOut = new DoubleAnimation(0, -65, TimeSpan.FromMilliseconds(320))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn }
        };
        slideOut.Completed += (_, _) => Close();
        BannerTranslate.BeginAnimation(TranslateTransform.YProperty, slideOut);
    }

    public static void ShowBanner(string name)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            var banner = new WelcomeBannerWindow(name);
            banner.Show();
        });
    }
}
