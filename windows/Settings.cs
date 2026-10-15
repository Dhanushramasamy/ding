using System;
using System.IO;
using System.Text.Json;

namespace Ding
{
    /// <summary>The one user setting (which character delivers reminders), kept in %AppData%\Ding.</summary>
    public sealed class Settings
    {
        public string Character { get; set; } = "";
        /// <summary>Whether the "Ding is running in the tray" hint was shown on first launch.</summary>
        public bool WelcomeShown { get; set; }

        private static string FilePath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ding", "settings.json");

        public static Settings Load()
        {
            try
            {
                return File.Exists(FilePath)
                    ? JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings()
                    : new Settings();
            }
            catch
            {
                return new Settings();
            }
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
                File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
            }
            catch
            {
                // Losing the character choice isn't worth interrupting the user over.
            }
        }
    }
}
