using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using SkiaSharp;

namespace Ding
{
    /// <summary>
    /// Turns one of your pictures into a character. After you pick an image it asks how to
    /// use it, showing both results side by side: the subject cut out of its background,
    /// or the full image as it is.
    /// </summary>
    public partial class AddImageWindow : Window
    {
        /// <summary>Raised with the new character after it has been saved.</summary>
        public event Action<Character>? Added;

        private SKBitmap? _original;
        private SKBitmap? _subject;
        private bool _useSubject = true;
        private int _loadId;

        public AddImageWindow()
        {
            InitializeComponent();
            SourceInitialized += (_, _) => Native.RoundCorners(new WindowInteropHelper(this).Handle);
            Closed += (_, _) =>
            {
                _original?.Dispose();
                _subject?.Dispose();
            };
        }

        private void OnChoose(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Title = "Choose a photo or drawing",
                Filter = "Images|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif|All files|*.*",
            };
            if (dialog.ShowDialog(this) == true) Load(dialog.FileName);
        }

        private void OnDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files) Load(files[0]);
        }

        private void Load(string path)
        {
            var image = CustomCharacters.Load(path);
            if (image is null)
            {
                ShowError("That file couldn’t be opened as an image.");
                return;
            }
            ShowError(null);
            _original?.Dispose();
            _subject?.Dispose();
            _original = image;
            _subject = null;

            DropZone.Visibility = Visibility.Collapsed;
            ChoicePanel.Visibility = Visibility.Visible;
            AnotherButton.Visibility = Visibility.Visible;
            NameField.Text = Path.GetFileNameWithoutExtension(path);
            FullPreview.Source = ToBitmapSource(image);
            SubjectPreview.Source = null;
            SubjectStatus.Text = "Finding the subject…";
            SubjectStatus.Visibility = Visibility.Visible;
            SubjectDetail.Text = "Cut out the person, pet or object from its background.";
            Select(subject: true);

            // Subject lifting takes a moment; keep the window responsive meanwhile.
            var id = ++_loadId;
            var copy = image.Copy();
            Task.Run(() => CustomCharacters.ExtractSubject(copy)).ContinueWith(task =>
            {
                copy.Dispose();
                if (id != _loadId) { task.Result?.Dispose(); return; }
                _subject = task.Result;
                if (_subject is null)
                {
                    SubjectStatus.Text = "No clear subject found";
                    SubjectDetail.Text = "No clear subject found in this image.";
                    SubjectOption.Opacity = 0.55;
                    Select(subject: false);
                }
                else
                {
                    SubjectStatus.Visibility = Visibility.Collapsed;
                    SubjectPreview.Source = ToBitmapSource(_subject);
                    SubjectOption.Opacity = 1;
                    Select(subject: _useSubject);
                }
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        private void OnPickSubject(object sender, MouseButtonEventArgs e)
        {
            if (_subject is not null) Select(subject: true);
        }

        private void OnPickFull(object sender, MouseButtonEventArgs e) => Select(subject: false);

        private void Select(bool subject)
        {
            _useSubject = subject;
            var accent = (Brush)FindResource("AccentBackground");
            var stroke = (Brush)FindResource("Stroke");
            SubjectOption.BorderBrush = subject ? accent : stroke;
            SubjectOption.BorderThickness = new Thickness(subject ? 2.5 : 1);
            FullOption.BorderBrush = subject ? stroke : accent;
            FullOption.BorderThickness = new Thickness(subject ? 1 : 2.5);
            SubjectMark.Text = subject ? "●" : "○";
            FullMark.Text = subject ? "○" : "●";
            SubjectMark.Foreground = (Brush)FindResource(subject ? "AccentText" : "TextSecondary");
            FullMark.Foreground = (Brush)FindResource(subject ? "TextSecondary" : "AccentText");
            AddButton.IsEnabled = _original is not null && (!subject || _subject is not null);
        }

        private void OnAdd(object sender, RoutedEventArgs e)
        {
            var picture = _useSubject ? _subject : _original;
            if (picture is null) return;
            try
            {
                var character = CustomCharacters.Save(picture, NameField.Text);
                Added?.Invoke(character);
                Close();
            }
            catch (Exception ex)
            {
                ShowError("Couldn’t save the image: " + ex.Message);
            }
        }

        private void OnCancel(object sender, RoutedEventArgs e) => Close();

        private void ShowError(string? message)
        {
            ErrorText.Text = message ?? "";
            ErrorText.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
        }

        private static BitmapSource ToBitmapSource(SKBitmap bitmap)
        {
            using var data = SKImage.FromBitmap(bitmap).Encode(SKEncodedImageFormat.Png, 100);
            using var stream = new MemoryStream(data.ToArray());
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = stream;
            image.EndInit();
            image.Freeze();
            return image;
        }
    }
}
