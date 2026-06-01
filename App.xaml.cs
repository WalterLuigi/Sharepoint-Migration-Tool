using System.Windows;
using SharePointMigrationTool.Services;

namespace SharePointMigrationTool;

/// <summary>
/// Application entry point
/// </summary>
public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Set up exception handling
        DispatcherUnhandledException += (s, args) =>
        {
            MessageBox.Show($"An error occurred: {args.Exception.Message}\n\n{args.Exception.StackTrace}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
    }

    private void Application_Startup(object sender, StartupEventArgs e)
    {
        // Prevent WPF from shutting down when the dialog closes
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        // Debug: Show paths for troubleshooting
        try
        {
            var appRoot = PathHelper.ApplicationRoot;
            var scriptsPath = PathHelper.GetScriptsPath();
            var configPath = PathHelper.GetConfigPath();

            System.Diagnostics.Debug.WriteLine($"=== PATH DIAGNOSTICS ===");
            System.Diagnostics.Debug.WriteLine($"Application Root: {appRoot}");
            System.Diagnostics.Debug.WriteLine($"Scripts Path: {scriptsPath}");
            System.Diagnostics.Debug.WriteLine($"Config Path: {configPath}");
            System.Diagnostics.Debug.WriteLine($"Scripts Exists: {System.IO.Directory.Exists(scriptsPath)}");
            System.Diagnostics.Debug.WriteLine($"Config Exists: {System.IO.Directory.Exists(configPath)}");
            System.Diagnostics.Debug.WriteLine($"========================");
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Error resolving paths:\n\n{ex.Message}\n\n{ex.StackTrace}",
                "Path Error", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown();
            return;
        }

        // Check prerequisites first
        var prereqWindow = new PrerequisitesWindow();
        bool? dialogResult = prereqWindow.ShowDialog();

        if (dialogResult == true && prereqWindow.CanProceed)
        {
            // Prerequisites met, show main window
            // Switch back to OnLastWindowClose so app closes when MainWindow closes
            ShutdownMode = ShutdownMode.OnLastWindowClose;

            var mainWindow = new MainWindow();
            mainWindow.Show();
        }
        else
        {
            // Prerequisites not met or user cancelled
            Shutdown();
        }
    }
}