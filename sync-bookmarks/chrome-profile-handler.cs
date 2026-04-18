using System;
using System.Diagnostics;
using Microsoft.Win32;

class ChromeProfileHandler {
    [STAThread]
    static void Main(string[] args) {
        if (args.Length == 0) return;

        // Format: chrome-profile:///ProfileDir/encodedUrl
        // Profile is in the path (not host) to avoid Uri normalising it to lowercase
        string prefix = "chrome-profile:///";
        string raw = args[0];
        if (!raw.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return;

        string rest = raw.Substring(prefix.Length);
        int sep = rest.IndexOf('/');
        if (sep < 0) return;

        string profileDir = Uri.UnescapeDataString(rest.Substring(0, sep));
        string url        = Uri.UnescapeDataString(rest.Substring(sep + 1));

        string chromePath = "chrome.exe";
        try {
            using (var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe")) {
                if (key != null) { object v = key.GetValue(null); if (v != null) chromePath = v.ToString(); }
            }
        } catch {}

        Process.Start(chromePath, string.Format("--profile-directory=\"{0}\" \"{1}\"", profileDir, url));
    }
}
