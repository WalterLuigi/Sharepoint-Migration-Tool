using System.Diagnostics;
using System.IO;
using System.Windows;
using SharePointMigrationTool.Services;

namespace SharePointMigrationTool;

public partial class PrerequisitesWindow : Window
{
    private readonly PrerequisitesService _prereqService = new();
    private PrerequisiteStatus? _status;
    public bool CanProceed { get; private set; }

    public PrerequisitesWindow()
    {
        InitializeComponent();
        _prereqService.StatusChanged += OnStatusChanged;
        Loaded += PrerequisitesWindow_Loaded;

        // Debug: Show resolved paths
        var scriptsPath = PathHelper.GetScriptsPath();
        var configPath = PathHelper.GetConfigPath();
        var appRoot = PathHelper.ApplicationRoot;

        System.Diagnostics.Debug.WriteLine($"Application Root: {appRoot}");
        System.Diagnostics.Debug.WriteLine($"Scripts Path: {scriptsPath}");
        System.Diagnostics.Debug.WriteLine($"Config Path: {configPath}");
        System.Diagnostics.Debug.WriteLine($"Scripts Exists: {Directory.Exists(scriptsPath)}");
    }

    private void PrerequisitesWindow_Loaded(object sender, RoutedEventArgs e)
    {
        _ = CheckPrerequisitesAsync();
    }

    private async Task CheckPrerequisitesAsync()
    {
        await Task.Run(() =>
        {
            _status = _prereqService.CheckPrerequisites();
        });

        UpdateUI();
    }

    private void UpdateUI()
    {
        if (_status == null) return;

        // PowerShell 7 status
        if (_status.PowerShell7Installed)
        {
            PowerShellStatus.Text = "Installed";
            PowerShellStatus.Foreground = System.Windows.Media.Brushes.Green;
            InstallPowerShellBtn.Visibility = Visibility.Collapsed;
        }
        else
        {
            PowerShellStatus.Text = "Not Found";
            PowerShellStatus.Foreground = System.Windows.Media.Brushes.Red;
            InstallPowerShellBtn.Visibility = Visibility.Visible;
        }

        // PnP PowerShell status
        if (_status.PnPInstalled)
        {
            PnPStatus.Text = "Installed";
            PnPStatus.Foreground = System.Windows.Media.Brushes.Green;
            InstallPnPBtn.Visibility = Visibility.Collapsed;
        }
        else if (_status.PowerShell7Installed)
        {
            PnPStatus.Text = "Not Found";
            PnPStatus.Foreground = System.Windows.Media.Brushes.Red;
            InstallPnPBtn.Visibility = Visibility.Visible;
        }
        else
        {
            PnPStatus.Text = "Requires PowerShell 7";
            PnPStatus.Foreground = System.Windows.Media.Brushes.Gray;
            InstallPnPBtn.Visibility = Visibility.Collapsed;
        }

        // Enable continue button if all installed
        ContinueBtn.IsEnabled = _status.AllInstalled;
    }

    private void OnStatusChanged(object? sender, string status)
    {
        Dispatcher.Invoke(() =>
        {
            if (OutputLog.Text.Length > 0)
                OutputLog.Text += Environment.NewLine;
            OutputLog.Text += status;
            OutputLog.ScrollToEnd();
        });
    }

    private void InstallPowerShell_Click(object sender, RoutedEventArgs e)
    {
        var url = _prereqService.GetPowerShell7DownloadUrl();
        LogOutput("Opening PowerShell 7 download page...");
        LogOutput($"URL: {url}");

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true
            });

            MessageBox.Show(
                "A browser will open to download PowerShell 7.\n\n" +
                "Please install PowerShell 7, then restart this application.",
                "Download PowerShell 7",
                MessageBoxButton.OK,
                MessageBoxImage.Information);

            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            LogOutput($"Failed to open browser: {ex.Message}");
            MessageBox.Show(
                $"Failed to open browser. Please visit:\n{url}",
                "Manual Download",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private async void InstallPnP_Click(object sender, RoutedEventArgs e)
    {
        InstallPnPBtn.IsEnabled = false;
        PnPStatus.Text = "Installing...";
        PnPStatus.Foreground = System.Windows.Media.Brushes.Orange;

        try
        {
            var result = await _prereqService.InstallPnPPowerShellAsync(LogOutput);

            if (result.Success)
            {
                PnPStatus.Text = "Installed";
                PnPStatus.Foreground = System.Windows.Media.Brushes.Green;
                InstallPnPBtn.Visibility = Visibility.Collapsed;

                // Recheck status
                await CheckPrerequisitesAsync();
            }
            else
            {
                PnPStatus.Text = $"Failed: {result.Error}";
                PnPStatus.Foreground = System.Windows.Media.Brushes.Red;
                InstallPnPBtn.IsEnabled = true;
            }
        }
        catch (Exception ex)
        {
            PnPStatus.Text = $"Error: {ex.Message}";
            PnPStatus.Foreground = System.Windows.Media.Brushes.Red;
            InstallPnPBtn.IsEnabled = true;
        }
    }

    private void LogOutput(string message)
    {
        Dispatcher.Invoke(() =>
        {
            if (OutputLog.Text.Length > 0)
                OutputLog.Text += Environment.NewLine;
            OutputLog.Text += message;
            OutputLog.ScrollToEnd();
        });
    }

    private void Continue_Click(object sender, RoutedEventArgs e)
    {
        CanProceed = true;
        DialogResult = true;
        Close();
    }

    private void Exit_Click(object sender, RoutedEventArgs e)
    {
        CanProceed = false;
        DialogResult = false;
        Close();
    }

    private void Window_Closed(object sender, EventArgs e)
    {
        _prereqService.StatusChanged -= OnStatusChanged;
    }
}