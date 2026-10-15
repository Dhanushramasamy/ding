using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace Ding
{
    /// <summary>The reminder card: just the message and Snooze / Done. Never steals focus.</summary>
    public partial class ReminderCard : Window
    {
        public event Action? DoneClicked;
        public event Action? SnoozeClicked;

        /// <summary>Shadow margin around the card, in DIPs (matches the Grid margin).</summary>
        public const double ShadowMargin = 28;

        public ReminderCard(string message)
        {
            InitializeComponent();
            MessageText.Text = message;
            SourceInitialized += (_, _) =>
                Native.AddExStyle(new WindowInteropHelper(this).Handle, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
        }

        public IntPtr Handle => new WindowInteropHelper(this).Handle;

        /// <summary>Grows up out of the character.</summary>
        public void Reveal()
        {
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            var time = TimeSpan.FromMilliseconds(350);
            Card.BeginAnimation(OpacityProperty, new DoubleAnimation(1, time) { EasingFunction = ease });
            CardScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, time) { EasingFunction = ease });
            CardScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, time) { EasingFunction = ease });
            CardOffset.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, time) { EasingFunction = ease });
        }

        /// <summary>Slides up and away.</summary>
        public void Dismiss()
        {
            IsHitTestVisible = false;
            var ease = new CubicEase { EasingMode = EasingMode.EaseIn };
            var time = TimeSpan.FromMilliseconds(300);
            Card.BeginAnimation(OpacityProperty, new DoubleAnimation(0, time) { EasingFunction = ease });
            CardOffset.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-50, time) { EasingFunction = ease });
        }

        private void OnDone(object sender, RoutedEventArgs e) => DoneClicked?.Invoke();

        private void OnSnooze(object sender, RoutedEventArgs e) => SnoozeClicked?.Invoke();
    }
}
