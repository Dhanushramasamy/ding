using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows.Threading;

namespace Ding
{
    public sealed class Reminder : INotifyPropertyChanged
    {
        public Reminder(DateTime fireDate, string message, string title)
        {
            FireDate = fireDate;
            Message = message;
            Title = title;
        }

        public DateTime FireDate { get; }
        public string Message { get; }
        /// <summary>What kind of reminder this was, e.g. "10 min timer" or "Alarm · 17:30".</summary>
        public string Title { get; }

        private string _remaining = "";
        /// <summary>"4:05" or "1:04:05" until it fires; refreshed every second.</summary>
        public string Remaining
        {
            get => _remaining;
            set { if (_remaining != value) { _remaining = value; OnChanged(); } }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnChanged([CallerMemberName] string? name = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    /// <summary>
    /// Pending timers and alarms, ticking once a second while any exist.
    /// Held in memory only, like the Mac app: quitting drops them.
    /// </summary>
    public sealed class ReminderStore
    {
        private readonly DispatcherTimer _ticker = new() { Interval = TimeSpan.FromSeconds(1) };

        public ReminderStore()
        {
            _ticker.Tick += (_, _) => Tick();
        }

        public ObservableCollection<Reminder> Reminders { get; } = new();

        public event Action<Reminder>? Fired;
        /// <summary>Raised every second while reminders are pending (for the tray tooltip).</summary>
        public event Action? Ticked;

        public Reminder? Next => Reminders.FirstOrDefault();

        public void AddAfter(TimeSpan delay, string message, string? title = null)
        {
            var minutes = (int)Math.Round(delay.TotalMinutes);
            Add(new Reminder(DateTime.Now + delay, message, title ?? $"{minutes} min timer"));
        }

        /// <summary>Fires at the next occurrence of a clock time: today, or tomorrow if it has passed.</summary>
        public void AddAlarm(TimeSpan timeOfDay, string message)
        {
            var fire = DateTime.Today + timeOfDay;
            if (fire <= DateTime.Now) fire = fire.AddDays(1);
            Add(new Reminder(fire, message, $"Alarm · {fire:HH:mm}"));
        }

        public void Cancel(Reminder reminder)
        {
            Reminders.Remove(reminder);
            if (Reminders.Count == 0) _ticker.Stop();
            Ticked?.Invoke();
        }

        private void Add(Reminder reminder)
        {
            var index = 0;
            while (index < Reminders.Count && Reminders[index].FireDate <= reminder.FireDate) index++;
            Reminders.Insert(index, reminder);
            Refresh();
            _ticker.Start();
        }

        private void Tick()
        {
            var now = DateTime.Now;
            foreach (var due in Reminders.Where(r => r.FireDate <= now).ToList())
            {
                Reminders.Remove(due);
                Fired?.Invoke(due);
            }
            if (Reminders.Count == 0) _ticker.Stop();
            Refresh();
        }

        private void Refresh()
        {
            var now = DateTime.Now;
            foreach (var r in Reminders) r.Remaining = Format(r.FireDate - now);
            Ticked?.Invoke();
        }

        public static string Format(TimeSpan left)
        {
            var total = Math.Max(0, (int)Math.Ceiling(left.TotalSeconds));
            int h = total / 3600, m = total % 3600 / 60, s = total % 60;
            return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m}:{s:00}";
        }
    }
}
