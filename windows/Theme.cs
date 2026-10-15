using System;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using Windows.UI.ViewManagement;

namespace Ding
{
    /// <summary>
    /// Follows the Windows light/dark setting and accent colour, like the Mac app follows
    /// macOS. Colours are app resources, so every window updates when the user switches.
    /// </summary>
    internal static class Theme
    {
        public static bool IsDark
        {
            get
            {
                try
                {
                    using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                    return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
                }
                catch
                {
                    return false;
                }
            }
        }

        public static void Apply()
        {
            var dark = IsDark;
            var r = Application.Current.Resources;

            r["PanelBackground"] = Brush(dark ? "#202020" : "#F3F3F3");
            r["Surface"] = Brush(dark ? "#2B2B2B" : "#FFFFFF");
            r["CardBackground"] = Brush(dark ? "#2C2C2C" : "#FCFCFC");
            r["TextPrimary"] = Brush(dark ? "#FFFFFF" : "#1A1A1A");
            r["TextSecondary"] = Brush(dark ? "#B8B8B8" : "#616161");
            r["Subtle"] = Brush(dark ? "#0FFFFFFF" : "#08000000");
            r["SubtleHover"] = Brush(dark ? "#18FFFFFF" : "#10000000");
            r["Stroke"] = Brush(dark ? "#3D3D3D" : "#E2E2E2");

            // Windows 11 uses a lighter accent with dark text in dark mode, a deeper one with white text in light mode.
            var accent = Accent(dark ? UIColorType.AccentLight2 : UIColorType.AccentDark1, dark ? "#99EBFF" : "#005FB8");
            r["AccentBackground"] = new SolidColorBrush(accent);
            r["AccentForeground"] = Brush(dark ? "#000000" : "#FFFFFF");
            r["AccentText"] = new SolidColorBrush(Accent(dark ? UIColorType.AccentLight2 : UIColorType.AccentDark1, dark ? "#99EBFF" : "#005FB8"));
        }

        private static Color Accent(UIColorType type, string fallback)
        {
            try
            {
                var c = new UISettings().GetColorValue(type);
                return Color.FromArgb(c.A, c.R, c.G, c.B);
            }
            catch
            {
                return (Color)ColorConverter.ConvertFromString(fallback);
            }
        }

        private static SolidColorBrush Brush(string hex)
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            brush.Freeze();
            return brush;
        }
    }
}
