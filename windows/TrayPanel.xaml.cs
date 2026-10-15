using System;
using System.Collections.Specialized;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;

namespace Ding
{
    /// <summary>The panel that opens from the tray icon: the Windows twin of the Mac menu panel.</summary>
    public partial class TrayPanel : Window
    {
        private static readonly int[] PresetMinutes = { 1, 5, 10, 25, 45 };

        private readonly ReminderStore _store;
        private readonly Settings _settings;
        private readonly Action _preview;
        private readonly Action _hideEverything;
        private int _minutes = 10;
        private DateTime _hiddenAt = DateTime.MinValue;

        public TrayPanel(ReminderStore store, Settings settings, Action preview, Action hideEverything)
        {
            InitializeComponent();
            _store = store;
            _settings = settings;
            _preview = preview;
            _hideEverything = hideEverything;

            foreach (var minutes in PresetMinutes)
            {
                var button = new Button
                {
                    Content = $"{minutes}m",
                    Style = (Style)FindResource("SubtleButton"),
                    Margin = new Thickness(0, 0, minutes == PresetMinutes[^1] ? 0 : 6, 0),
                    Padding = new Thickness(0, 6, 0, 6),
                };
                button.Click += (_, _) => StartTimer(minutes);
                Presets.Children.Add(button);
            }

            UpcomingList.ItemsSource = store.Reminders;
            store.Reminders.CollectionChanged += OnRemindersChanged;
            RefreshUpcoming();
            BuildCharacterChips();
            ResetAlarmField();

            SourceInitialized += (_, _) => Native.RoundCorners(new WindowInteropHelper(this).Handle);
            Deactivated += (_, _) => HidePanel();
        }

        /// <summary>True for a moment after the panel hid itself, so the tray click that caused it doesn't reopen it.</summary>
        public bool JustHid => (DateTime.Now - _hiddenAt).TotalMilliseconds < 300;

        public void ShowPanel()
        {
            ResetAlarmField();
            Show();
            UpdateLayout();
            // Bottom-right, just above the taskbar, like Windows' own flyouts.
            var area = SystemParameters.WorkArea;
            Left = area.Right - ActualWidth;
            Top = area.Bottom - ActualHeight;
            Activate();
            MessageField.Focus();
        }

        public void HidePanel()
        {
            if (!IsVisible) return;
            Hide();
            _hiddenAt = DateTime.Now;
        }

        private void BuildCharacterChips()
        {
            CharacterChips.Children.Clear();
            var characters = Character.All();
            var chosen = Chosen(characters);
            foreach (var character in characters)
            {
                var chip = new RadioButton
                {
                    Content = character.Name,
                    GroupName = "Character",
                    Style = (Style)FindResource("Chip"),
                    IsChecked = character.Name == chosen?.Name,
                    Margin = new Thickness(0, 0, 6, 6),
                };
                chip.Checked += (_, _) =>
                {
                    _settings.Character = character.Name;
                    _settings.Save();
                    RemoveButton.Visibility = character.IsCustom ? Visibility.Visible : Visibility.Collapsed;
                };
                CharacterChips.Children.Add(chip);
            }
            RemoveButton.Visibility = chosen?.IsCustom == true ? Visibility.Visible : Visibility.Collapsed;
        }

        private void OnAddImage(object sender, RoutedEventArgs e)
        {
            HidePanel();
            var window = new AddImageWindow();
            window.Added += character =>
            {
                _settings.Character = character.Name;
                _settings.Save();
                BuildCharacterChips();
            };
            window.Show();
            window.Activate();
        }

        private void OnRemoveImage(object sender, RoutedEventArgs e)
        {
            var chosen = Chosen();
            if (chosen is null || !chosen.IsCustom) return;
            CustomCharacters.Remove(chosen);
            _settings.Character = "";
            _settings.Save();
            BuildCharacterChips();
        }

        /// <summary>The saved character, or the first one available.</summary>
        public Character? Chosen(System.Collections.Generic.IReadOnlyList<Character>? all = null)
        {
            all ??= Character.All();
            foreach (var c in all) if (c.Name == _settings.Character) return c;
            return all.Count > 0 ? all[0] : null;
        }

        private void OnRemindersChanged(object? sender, NotifyCollectionChangedEventArgs e) => RefreshUpcoming();

        private void RefreshUpcoming() =>
            UpcomingSection.Visibility = _store.Reminders.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

        private string ReminderText
        {
            get
            {
                var text = MessageField.Text.Trim();
                return text.Length == 0 ? "Time’s up." : text;
            }
        }

        private void StartTimer(int minutes)
        {
            _store.AddAfter(TimeSpan.FromMinutes(minutes), ReminderText);
            MessageField.Clear();
        }

        private void ResetAlarmField()
        {
            AlarmField.Text = DateTime.Now.AddHours(1).ToString("HH:mm", CultureInfo.CurrentCulture);
            AlarmHint.Visibility = Visibility.Collapsed;
        }

        private void OnMessageChanged(object sender, TextChangedEventArgs e) =>
            MessagePlaceholder.Visibility = MessageField.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;

        private void OnMessageKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter) StartTimer(_minutes);
            if (e.Key == Key.Escape) HidePanel();
        }

        private void OnStart(object sender, RoutedEventArgs e) => StartTimer(_minutes);

        private void OnMinus(object sender, RoutedEventArgs e) => SetMinutes(_minutes - (_minutes > 10 ? 5 : 1));

        private void OnPlus(object sender, RoutedEventArgs e) => SetMinutes(_minutes + (_minutes >= 10 ? 5 : 1));

        private void SetMinutes(int minutes)
        {
            _minutes = Math.Clamp(minutes, 1, 600);
            MinutesText.Text = $"{_minutes} min";
        }

        private void OnSetAlarm(object sender, RoutedEventArgs e)
        {
            if (!DateTime.TryParse(AlarmField.Text, CultureInfo.CurrentCulture, DateTimeStyles.NoCurrentDateDefault, out var time))
            {
                AlarmHint.Visibility = Visibility.Visible;
                return;
            }
            AlarmHint.Visibility = Visibility.Collapsed;
            _store.AddAlarm(time.TimeOfDay, ReminderText);
            MessageField.Clear();
        }

        private void OnCancel(object sender, RoutedEventArgs e)
        {
            if (sender is FrameworkElement { Tag: Reminder reminder }) _store.Cancel(reminder);
        }

        private void OnPreview(object sender, RoutedEventArgs e)
        {
            HidePanel();
            _preview();
        }

        private void OnHideEverything(object sender, RoutedEventArgs e)
        {
            HidePanel();
            _hideEverything();
        }

        private void OnQuit(object sender, RoutedEventArgs e) => Application.Current.Shutdown();
    }
}
