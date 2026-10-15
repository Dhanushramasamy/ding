using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Ding
{
    /// <summary>Covers one monitor completely (taskbar included) with a clock. Apps underneath keep running.</summary>
    public partial class CoverWindow : Window
    {
        private readonly System.Drawing.Rectangle _bounds;
        private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(1) };

        public event Action? ShowRequested;

        public CoverWindow(Forms.Screen screen)
        {
            InitializeComponent();
            _bounds = screen.Bounds;
            _clock.Tick += (_, _) => UpdateClock();
            UpdateClock();
            _clock.Start();

            SourceInitialized += (_, _) =>
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                Native.AddExStyle(hwnd, Native.WS_EX_TOOLWINDOW);
                Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, _bounds.Left, _bounds.Top, _bounds.Width, _bounds.Height,
                                    Native.SWP_SHOWWINDOW);
            };
            KeyDown += (_, e) => { if (e.Key == Key.Escape) ShowRequested?.Invoke(); };
            Closed += (_, _) => _clock.Stop();
        }

        private void UpdateClock()
        {
            var now = DateTime.Now;
            ClockText.Text = now.ToString("t", CultureInfo.CurrentCulture);
            DateText.Text = now.ToString("dddd, d MMMM", CultureInfo.CurrentCulture);
        }

        private void OnShow(object sender, RoutedEventArgs e) => ShowRequested?.Invoke();
    }

    /// <summary>Hide Everything: one cover per monitor; Esc, the button or Ctrl+Alt+H brings everything back.</summary>
    public sealed class CoverController
    {
        private readonly List<CoverWindow> _covers = new();

        public bool IsShowing => _covers.Count > 0;

        public void Toggle()
        {
            if (IsShowing) Hide(); else Show();
        }

        public void Show()
        {
            if (IsShowing) return;
            foreach (var screen in Forms.Screen.AllScreens)
            {
                var cover = new CoverWindow(screen);
                cover.ShowRequested += Hide;
                cover.Show();
                _covers.Add(cover);
            }
            // Focus one so Esc works straight away.
            _covers[0].Activate();
        }

        public void Hide()
        {
            foreach (var cover in _covers) cover.Close();
            _covers.Clear();
        }
    }
}
