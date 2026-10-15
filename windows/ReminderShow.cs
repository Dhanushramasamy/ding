using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SkiaSharp;
using SkiaSharp.Skottie;
using SkiaSharp.Views.Desktop;
using SkiaSharp.Views.WPF;
using Forms = System.Windows.Forms;

namespace Ding
{
    /// <summary>
    /// Delivers a reminder with the chosen character:
    /// - a Lottie character runs in from a random point on any edge and brakes to a stop in
    ///   the middle of the screen, timed so its legs land on the standing pose as it arrives;
    /// - your own image hop-runs in the same way (a still picture has no legs to animate).
    /// The card then grows out of the character. Done or Snooze slides it away and the
    /// character leaves toward another edge.
    ///
    /// The character and the card are two small windows moved across the screen, so
    /// nothing else on screen is covered or blocked.
    /// </summary>
    public sealed class ReminderShow
    {
        private enum Phase { RunIn, Present, RunOut, Done }
        private enum Edge { Left, Right, Top, Bottom }

        public event Action? Snoozed;
        public event Action? Finished;

        private const double RunSpeed = 560;      // DIPs per second
        private const double Braking = 700;       // DIPs per second², an even slow-down
        private const double Acceleration = 1200;
        private const double DrawnHeight = 180;   // height of the character itself
        private const double HopRoom = 24;        // headroom in the image window for hopping

        private readonly Reminder _reminder;
        private readonly Animation? _animation;
        private readonly ArtBounds _art;
        private readonly double _cycleFrames;
        private readonly BitmapSource? _picture;
        private readonly Size _pictureSize;
        private readonly System.Drawing.Rectangle _area;   // work area, physical pixels
        private readonly double _scale;                    // display scaling of that monitor
        private readonly Stopwatch _clock = new();
        private readonly Random _random = new();

        private Window? _actor;
        private FrameworkElement? _actorContent;
        private ReminderCard? _card;
        private Phase _phase = Phase.Done;
        private TimeSpan _last;
        private Point _position;                  // feet, DIPs from the work area's top-left
        private Vector _direction = new(1, 0);
        private double _facing = 1;
        private Edge _entry;
        private double _velocity;
        private double _frame;
        private double _speed = 1;
        private double _hop;
        private bool _finished;

        public ReminderShow(Reminder reminder, Character? character)
        {
            _reminder = reminder;
            if (character?.Kind == CharacterKind.Lottie)
            {
                _animation = character.LoadAnimation();
            }
            else if (character?.Kind == CharacterKind.Image && File.Exists(character.Path))
            {
                _picture = LoadPicture(character.Path);
                if (_picture is not null)
                {
                    var aspect = _picture.PixelWidth / (double)Math.Max(1, _picture.PixelHeight);
                    _pictureSize = new Size(DrawnHeight * aspect, DrawnHeight);
                    if (_pictureSize.Width > 300) _pictureSize = new Size(300, 300 / aspect);
                }
            }
            _art = _animation is null ? ArtBounds.Default : ArtBounds.Measure(_animation);
            _cycleFrames = _animation is null ? 1 : Math.Max(1, _animation.Duration.TotalSeconds * _animation.Fps);

            Native.GetCursorPos(out var cursor);
            var screen = Forms.Screen.FromPoint(new System.Drawing.Point(cursor.X, cursor.Y));
            _area = screen.WorkingArea;
            _scale = Native.ScaleAt(_area.Left + _area.Width / 2, _area.Top + _area.Height / 2);
        }

        private bool HasActor => _animation is not null || _picture is not null;
        private double Width => _area.Width / _scale;
        private double Height => _area.Height / _scale;
        private Point StopPoint => new(Width / 2, Height * 0.62);
        /// <summary>Side of the square a Lottie animation is drawn into, so the drawing itself is DrawnHeight tall.</summary>
        private double BoxSide => DrawnHeight / Math.Max(_art.Bottom - _art.Top, 0.2);
        private double ActorHeight => _animation is not null ? (_art.Bottom - _art.Top) * BoxSide : _pictureSize.Height;
        private double ActorWidth => _animation is not null ? BoxSide : _pictureSize.Width;

        public void Start()
        {
            if (HasActor)
            {
                _actor = MakeActorWindow();
                _entry = (Edge)_random.Next(4);
                _position = PointOn(_entry);
                Aim(StopPoint);
                _velocity = RunSpeed;
                _phase = Phase.RunIn;
                Place();
                _actor.Show();
            }
            else
            {
                _position = StopPoint;
                ShowCard();
            }
            _clock.Start();
            CompositionTarget.Rendering += OnFrame;
        }

        // MARK: Windows

        private Window MakeActorWindow()
        {
            FrameworkElement content;
            Size size;
            if (_animation is not null)
            {
                var element = new SKElement { IgnorePixelScaling = false };
                element.PaintSurface += OnPaintCharacter;
                content = element;
                size = new Size(BoxSide, BoxSide);
            }
            else
            {
                content = new Image
                {
                    Source = _picture,
                    Stretch = Stretch.Uniform,
                    Width = _pictureSize.Width,
                    Height = _pictureSize.Height,
                    VerticalAlignment = VerticalAlignment.Bottom,
                };
                RenderOptions.SetBitmapScalingMode(content, BitmapScalingMode.HighQuality);
                size = new Size(_pictureSize.Width + 40, _pictureSize.Height + HopRoom);
            }
            content.RenderTransformOrigin = _animation is not null ? new Point(0.5, 0.5) : new Point(0.5, 1);
            _actorContent = content;

            var window = new Window
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                Topmost = true,
                ShowInTaskbar = false,
                ShowActivated = false,
                ResizeMode = ResizeMode.NoResize,
                Left = -10000,
                Top = -10000,
                Width = size.Width,
                Height = size.Height,
                Content = new Grid { Children = { content } },
                Title = "Ding character",
            };
            window.SourceInitialized += (_, _) =>
            {
                var hwnd = new WindowInteropHelper(window).Handle;
                // Purely visual: every click passes straight through to what's underneath.
                Native.AddExStyle(hwnd, Native.WS_EX_TRANSPARENT | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
            };
            return window;
        }

        private static BitmapSource? LoadPicture(string path)
        {
            try
            {
                var image = new BitmapImage();
                image.BeginInit();
                image.CacheOption = BitmapCacheOption.OnLoad;
                image.UriSource = new Uri(path);
                image.EndInit();
                image.Freeze();
                return image;
            }
            catch
            {
                return null;
            }
        }

        /// <summary>Moves a window to a spot given in DIPs from the work area's top-left.</summary>
        private void Move(Window window, double left, double top, double width, double height)
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;
            Native.SetWindowPos(hwnd, Native.HWND_TOPMOST,
                                _area.Left + (int)Math.Round(left * _scale), _area.Top + (int)Math.Round(top * _scale),
                                (int)Math.Round(width * _scale), (int)Math.Round(height * _scale),
                                Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
        }

        // MARK: Motion

        private void OnFrame(object? sender, EventArgs e)
        {
            var now = _clock.Elapsed;
            var dt = Math.Clamp((now - _last).TotalSeconds, 0, 1.0 / 30);
            _last = now;
            if (dt <= 0) return;

            switch (_phase)
            {
                case Phase.RunIn:
                    RunIn(dt);
                    break;
                case Phase.RunOut:
                    _velocity = Math.Min(RunSpeed, _velocity + Acceleration * dt);
                    Step(dt);
                    _speed = Math.Max(0.4, _velocity / RunSpeed);
                    var margin = ActorWidth + ActorHeight;
                    if (_position.X < -margin || _position.X > Width + margin || _position.Y < -margin || _position.Y > Height + margin)
                    {
                        _phase = Phase.Done;
                        Finish();
                    }
                    break;
            }

            if (_animation is not null && _speed > 0)
            {
                _frame = (_frame + dt * _animation.Fps * _speed) % _cycleFrames;
            }
            Place();
        }

        /// <summary>
        /// Full speed, then an even brake that ends exactly at the centre. For animations the
        /// leg cycle is paced while braking so the standing pose comes up as it stops.
        /// </summary>
        private void RunIn(double dt)
        {
            var remaining = (StopPoint - _position).Length;
            var brakeFrom = Math.Sqrt(2 * Braking * remaining);
            if (brakeFrom < _velocity)
            {
                _velocity = Math.Max(0, brakeFrom);
                if (_animation is not null)
                {
                    var timeLeft = _velocity / Braking;
                    var framesLeft = (_art.StandFrame - _frame) % _cycleFrames;
                    if (framesLeft < 0) framesLeft += _cycleFrames;
                    if (timeLeft > 0.05)
                    {
                        var natural = _velocity / RunSpeed;
                        // Stay close to the natural pace; only nudge it to line the pose up.
                        _speed = Math.Clamp(framesLeft / (_animation.Fps * timeLeft), natural * 0.6, natural * 1.6 + 0.2);
                    }
                }
            }
            else
            {
                _velocity = RunSpeed;
                _speed = 1;
            }
            Step(dt);

            if (remaining < 0.5 || _velocity < 1)
            {
                _position = StopPoint;
                _velocity = 0;
                _speed = 0;
                _hop = 0;
                _frame = _art.StandFrame;
                ShowCard();
            }
        }

        private void Step(double dt)
        {
            var distance = _velocity * dt;
            _position += _direction * distance;
            _hop += distance / 110 * Math.PI;
        }

        private Point PointOn(Edge edge)
        {
            var margin = ActorWidth / 2 + 20;
            return edge switch
            {
                Edge.Left => new Point(-margin, Height * (0.3 + _random.NextDouble() * 0.55)),
                Edge.Right => new Point(Width + margin, Height * (0.3 + _random.NextDouble() * 0.55)),
                Edge.Top => new Point(Width * (0.15 + _random.NextDouble() * 0.7), -20),
                _ => new Point(Width * (0.15 + _random.NextDouble() * 0.7), Height + ActorHeight + 20),
            };
        }

        private void Aim(Point target)
        {
            var v = target - _position;
            if (v.Length > 0.001) v.Normalize();
            _direction = v;
            // Face the way it's going; straight up or down keeps the current facing.
            if (_direction.X < -0.2) _facing = -1;
            else if (_direction.X > 0.2) _facing = 1;
        }

        private void Place()
        {
            if (_actor is null || _actorContent is null) return;
            if (_animation is not null)
            {
                var box = BoxSide;
                // The drawing's feet (bottom, horizontal centre) land on the position.
                Move(_actor, _position.X - _art.CenterX * box, _position.Y - _art.Bottom * box, box, box);
                _actorContent.RenderTransform = new ScaleTransform(_facing, 1);
                _actorContent.InvalidateVisual();
            }
            else
            {
                // Hop with the stride, lean into the run, squash a little on each landing.
                var pace = Math.Min(1, _velocity / RunSpeed * 1.5);
                var bounce = Math.Abs(Math.Sin(_hop));
                var lift = bounce * 18 * pace;
                var tilt = (4 + 3 * Math.Sin(_hop * 2)) * pace * _facing;
                var squash = (1 - bounce) * 0.06 * pace;
                var width = _pictureSize.Width + 40;
                var height = _pictureSize.Height + HopRoom;
                Move(_actor, _position.X - width / 2, _position.Y - height, width, height);
                var transform = new TransformGroup();
                transform.Children.Add(new ScaleTransform(1 + squash, 1 - squash));
                transform.Children.Add(new RotateTransform(tilt));
                transform.Children.Add(new TranslateTransform(0, -lift));
                _actorContent.RenderTransform = transform;
            }
        }

        private void OnPaintCharacter(object? sender, SKPaintSurfaceEventArgs e)
        {
            var canvas = e.Surface.Canvas;
            canvas.Clear(SKColors.Transparent);
            if (_animation is null) return;
            _animation.SeekFrame(_frame);
            _animation.Render(canvas, SKRect.Create(e.Info.Width, e.Info.Height));
        }

        // MARK: Card

        private void ShowCard()
        {
            _phase = Phase.Present;
            var card = new ReminderCard(_reminder.Message);
            card.DoneClicked += () => Dismiss(snooze: false);
            card.SnoozeClicked += () => Dismiss(snooze: true);
            card.Show();
            card.UpdateLayout();
            // Stand the card on top of the character's head (shadow margin included).
            var width = card.ActualWidth;
            var height = card.ActualHeight;
            var left = Math.Clamp(_position.X - width / 2, 0, Math.Max(0, Width - width));
            var top = Math.Max(0, _position.Y - ActorHeight - 18 - height + ReminderCard.ShadowMargin);
            Move(card, left, top, width, height);
            card.Reveal();
            _card = card;
        }

        private void Dismiss(bool snooze)
        {
            if (_phase != Phase.Present) return;
            if (snooze) Snoozed?.Invoke();
            _card?.Dismiss();

            if (!HasActor)
            {
                _phase = Phase.Done;
                var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
                timer.Tick += (_, _) => { timer.Stop(); Finish(); };
                timer.Start();
                return;
            }

            // Leave toward a different edge from the one it came in by.
            Edge exit;
            do { exit = (Edge)_random.Next(4); } while (exit == _entry);
            Aim(PointOn(exit));
            _velocity = 0;
            _speed = 0.4;
            _phase = Phase.RunOut;
        }

        private void Finish()
        {
            if (_finished) return;
            _finished = true;
            CompositionTarget.Rendering -= OnFrame;
            _actor?.Close();
            _card?.Close();
            Finished?.Invoke();
        }
    }
}
