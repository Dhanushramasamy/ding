using System;
using System.Collections.Generic;
using System.IO;
using System.Media;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace Ding
{
    /// <summary>
    /// Ding for Windows: lives in the system tray (no taskbar button, like the Mac app lives
    /// in the menu bar). Timers and alarms are set from the tray panel; when one is due the
    /// chosen character runs in and delivers it.
    /// </summary>
    public partial class App : Application
    {
        private const int HideEverythingHotkey = 1;

        private Mutex? _singleInstance;
        private Forms.NotifyIcon? _tray;
        private TrayPanel? _panel;
        private HwndSource? _hotkeyWindow;
        private readonly ReminderStore _store = new();
        private readonly Settings _settings = Settings.Load();
        private readonly CoverController _cover = new();
        private readonly List<ReminderShow> _shows = new();

        /// <summary>Set by the GitHub build: exercise every window, then exit 0 (or 1 on any error).</summary>
        private static bool SmokeTest => Environment.GetEnvironmentVariable("DING_SMOKE") == "1";
        private static string LogPath => Path.Combine(Path.GetTempPath(), "ding.log");

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            _singleInstance = new Mutex(true, "Ding.SingleInstance.v1", out var first);
            if (!first)
            {
                Shutdown();
                return;
            }

            DispatcherUnhandledException += (_, args) =>
            {
                Log("Unhandled: " + args.Exception);
                if (SmokeTest) Environment.Exit(1);
                args.Handled = true;
            };

            Theme.Apply();
            SystemEvents.UserPreferenceChanged += (_, _) => Dispatcher.Invoke(Theme.Apply);

            _panel = new TrayPanel(_store, _settings, Preview, _cover.Show);
            _store.Fired += Deliver;
            _store.Ticked += UpdateTooltip;
            _store.Reminders.CollectionChanged += (_, _) => UpdateTooltip();

            SetUpTray();
            RegisterHotkey();

            if (SmokeTest) RunSmokeTest();
        }

        protected override void OnExit(ExitEventArgs e)
        {
            if (_tray is not null)
            {
                _tray.Visible = false;
                _tray.Dispose();
            }
            if (_hotkeyWindow is not null) Native.UnregisterHotKey(_hotkeyWindow.Handle, HideEverythingHotkey);
            _singleInstance?.Dispose();
            base.OnExit(e);
        }

        // MARK: Reminders

        private void Deliver(Reminder reminder)
        {
            var show = new ReminderShow(reminder, _panel?.Chosen());
            show.Snoozed += () => _store.AddAfter(TimeSpan.FromMinutes(5), reminder.Message, "Snoozed 5 min");
            show.Finished += () => _shows.Remove(show);
            _shows.Add(show);
            show.Start();
            SystemSounds.Asterisk.Play();
        }

        private void Preview() =>
            Deliver(new Reminder(DateTime.Now, "Stand up and stretch.", "Preview"));

        // MARK: Tray

        private void SetUpTray()
        {
            var menu = new Forms.ContextMenuStrip();
            menu.Items.Add("Open Ding", null, (_, _) => _panel?.ShowPanel());
            menu.Items.Add("Hide Everything   Ctrl+Alt+H", null, (_, _) => _cover.Show());
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("Quit Ding", null, (_, _) => Shutdown());

            _tray = new Forms.NotifyIcon
            {
                Icon = LoadTrayIcon(),
                Text = "Ding",
                ContextMenuStrip = menu,
                Visible = true,
            };
            _tray.MouseClick += (_, args) =>
            {
                if (args.Button != Forms.MouseButtons.Left || _panel is null) return;
                if (_panel.IsVisible) _panel.HidePanel();
                else if (!_panel.JustHid) _panel.ShowPanel();
            };

            // Windows 11 tucks new tray icons into the overflow area, so say where Ding went.
            if (!_settings.WelcomeShown && !SmokeTest)
            {
                _tray.ShowBalloonTip(6000, "Ding is running",
                    "Click the Ding icon in the system tray (bottom-right, maybe under ^) to set a reminder.",
                    Forms.ToolTipIcon.None);
                _settings.WelcomeShown = true;
                _settings.Save();
            }
        }

        private static System.Drawing.Icon LoadTrayIcon()
        {
            var resource = GetResourceStream(new Uri("pack://application:,,,/Assets/Ding.ico"));
            return resource is null
                ? System.Drawing.SystemIcons.Application
                : new System.Drawing.Icon(resource.Stream, Forms.SystemInformation.SmallIconSize);
        }

        /// <summary>Tooltip doubles as the Mac menu bar countdown.</summary>
        private void UpdateTooltip()
        {
            if (_tray is null) return;
            var next = _store.Next;
            var text = next is null ? "Ding" : $"Ding · {next.Remaining} · {next.Message}";
            _tray.Text = text.Length > 63 ? text[..62] + "…" : text;
        }

        // MARK: Hotkey

        private void RegisterHotkey()
        {
            _hotkeyWindow = new HwndSource(new HwndSourceParameters("DingHotkeys") { Width = 0, Height = 0, WindowStyle = 0 });
            _hotkeyWindow.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
            {
                if (msg == Native.WM_HOTKEY && wParam.ToInt32() == HideEverythingHotkey)
                {
                    _cover.Toggle();
                    handled = true;
                }
                return IntPtr.Zero;
            });
            // Ctrl+Alt+H; if another app already owns it, Hide Everything still works from the panel.
            Native.RegisterHotKey(_hotkeyWindow.Handle, HideEverythingHotkey,
                                  Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_NOREPEAT, 0x48);
        }

        // MARK: Smoke test

        private void RunSmokeTest()
        {
            Log("Smoke test started");
            var steps = new (double At, Action Step)[]
            {
                (0.5, () => _panel?.ShowPanel()),
                (1.5, () => _panel?.HidePanel()),
                (2.0, () => _cover.Show()),
                (3.0, () => _cover.Hide()),
                (3.2, SmokeTestImageTools),
                (3.5, () => _store.AddAfter(TimeSpan.FromSeconds(1), "Smoke test reminder")),
                (14.0, () => { Log("Smoke test passed"); Shutdown(0); }),
            };
            foreach (var (at, step) in steps)
            {
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(at) };
                timer.Tick += (_, _) =>
                {
                    timer.Stop();
                    try { step(); }
                    catch (Exception ex) { Log("Step failed: " + ex); Environment.Exit(1); }
                };
                timer.Start();
            }
        }

        /// <summary>Opens the Add Image window and runs the subject model on a test picture.</summary>
        private static void SmokeTestImageTools()
        {
            var window = new AddImageWindow();
            window.Show();
            window.Close();
            using var picture = new SkiaSharp.SKBitmap(240, 240);
            using (var canvas = new SkiaSharp.SKCanvas(picture))
            {
                canvas.Clear(SkiaSharp.SKColors.SkyBlue);
                canvas.DrawCircle(120, 120, 70, new SkiaSharp.SKPaint { Color = SkiaSharp.SKColors.OrangeRed, IsAntialias = true });
            }
            var modelFound = File.Exists(Path.Combine(AppContext.BaseDirectory, "Assets", "Models", "u2netp.onnx"));
            using var subject = CustomCharacters.ExtractSubject(picture);
            Log($"Subject model present: {modelFound}; subject found: {subject is not null}");
            if (!modelFound) throw new InvalidOperationException("Subject model missing from the build");
        }

        private static void Log(string line)
        {
            try { File.AppendAllText(LogPath, $"{DateTime.Now:O} {line}{Environment.NewLine}"); }
            catch { /* logging must never crash the app */ }
        }
    }
}
