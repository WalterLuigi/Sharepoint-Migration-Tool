using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;
using SharePointMigrationTool.Models;
using SharePointMigrationTool.Services;
using SharePointMigrationTool;

namespace SharePointMigrationTool.ViewModels;

/// <summary>
/// Main window view model with manual MVVM implementation
/// </summary>
public class MainViewModel : INotifyPropertyChanged
{
    private readonly ConfigurationService _configService;
    private readonly CertificateService _certificateService;
    private readonly PowerShellService _powerShellService;
    private readonly AppRegistrationService _appRegService;
    private readonly MigrationService _migrationService;
    private readonly TeardownService _teardownService;

    private MigrationConfig _config = new();
    private string _outputLog = string.Empty;
    private string _statusMessage = "Ready";
    private string _setupStatus = "Setup Required";
    private bool _isRunning;

    public event PropertyChangedEventHandler? PropertyChanged;

    public MigrationConfig Config
    {
        get => _config;
        set { _config = value; OnPropertyChanged(); }
    }

    public string OutputLog
    {
        get => _outputLog;
        set { _outputLog = value; OnPropertyChanged(); }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        set { _statusMessage = value; OnPropertyChanged(); }
    }

    public string SetupStatus
    {
        get => _setupStatus;
        set { _setupStatus = value; OnPropertyChanged(); }
    }

    public bool IsRunning
    {
        get => _isRunning;
        set
        {
            _isRunning = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsNotRunning));
            OnPropertyChanged(nameof(IsSetupComplete));
            RaiseCanExecuteChanged();
        }
    }

    public bool IsNotRunning => !IsRunning;

    public bool IsSetupComplete
    {
        get
        {
            var status = _configService.GetStatus(Config);
            return status.IsComplete && IsNotRunning;
        }
    }

    // Commands
    public RelayCommand RegisterSourceAppCommand { get; }
    public RelayCommand RegisterTargetAppCommand { get; }
    public RelayCommand RemoveSourceAppCommand { get; }
    public RelayCommand RemoveTargetAppCommand { get; }
    public RelayCommand SaveConfigCommand { get; }
    public RelayCommand TestConnectionCommand { get; }
    public RelayCommand DryRunCommand { get; }
    public RelayCommand StartMigrationCommand { get; }
    public RelayCommand GhostbusterCommand { get; }
    public RelayCommand ClearLogCommand { get; }
    public RelayCommand ExportLogCommand { get; }

    public MainViewModel()
    {
        _configService = new ConfigurationService();
        _certificateService = new CertificateService();
        _powerShellService = new PowerShellService();
        _appRegService = new AppRegistrationService(_powerShellService, _configService);
        _migrationService = new MigrationService(_powerShellService, _configService);
        _teardownService = new TeardownService(_powerShellService, _configService, _certificateService);

        // Initialize commands
        RegisterSourceAppCommand = new RelayCommand(RegisterSourceApp, () => IsNotRunning);
        RegisterTargetAppCommand = new RelayCommand(RegisterTargetApp, () => IsNotRunning);
        RemoveSourceAppCommand = new RelayCommand(RemoveSourceApp, () => IsNotRunning);
        RemoveTargetAppCommand = new RelayCommand(RemoveTargetApp, () => IsNotRunning);
        SaveConfigCommand = new RelayCommand(SaveConfig, () => IsNotRunning);
        TestConnectionCommand = new RelayCommand(TestConnection, () => IsNotRunning);
        DryRunCommand = new RelayCommand(DryRun, () => IsSetupComplete);
        StartMigrationCommand = new RelayCommand(StartMigration, () => IsSetupComplete);
        GhostbusterCommand = new RelayCommand(Ghostbuster, () => IsSetupComplete);
        ClearLogCommand = new RelayCommand(ClearLog);
        ExportLogCommand = new RelayCommand(ExportLog);

        // Load configuration
        LoadConfiguration();
    }

    private void LoadConfiguration()
    {
        Config = _configService.Load();
        UpdateSetupStatus();
    }

    private void UpdateSetupStatus()
    {
        var status = _configService.GetStatus(Config);
        SetupStatus = status.StatusMessage;
        OnPropertyChanged(nameof(IsSetupComplete));
    }

    private void LogOutput(string message)
    {
        var timestamp = DateTime.Now.ToString("HH:mm:ss");
        OutputLog += $"[{timestamp}] {message}{Environment.NewLine}";
    }

    private void ClearLog()
    {
        OutputLog = string.Empty;
    }

    private void ExportLog()
    {
        if (string.IsNullOrWhiteSpace(OutputLog))
        {
            MessageBox.Show("No log content to export.", "Export Log",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var saveDialog = new SaveFileDialog
        {
            Title = "Export Log",
            Filter = "Text Files (*.txt)|*.txt|Log Files (*.log)|*.log|All Files (*.*)|*.*",
            DefaultExt = ".txt",
            FileName = $"migration_log_{DateTime.Now:yyyyMMdd_HHmmss}.txt"
        };

        if (saveDialog.ShowDialog() == true)
        {
            try
            {
                var header = $"SharePoint Migration Tool Log{Environment.NewLine}" +
                            $"Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}{Environment.NewLine}" +
                            $"Source: {Config.Migration.SourceSiteUrl}{Environment.NewLine}" +
                            $"Target: {Config.Migration.TargetSiteUrl}{Environment.NewLine}" +
                            $"Library: {Config.Migration.LibraryName}{Environment.NewLine}" +
                            $"{new string('=', 60)}{Environment.NewLine}{Environment.NewLine}";

                File.WriteAllText(saveDialog.FileName, header + OutputLog);
                LogOutput($"Log exported to: {saveDialog.FileName}");
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to export log: {ex.Message}", "Export Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private void RaiseCanExecuteChanged()
    {
        RegisterSourceAppCommand.RaiseCanExecuteChanged();
        RegisterTargetAppCommand.RaiseCanExecuteChanged();
        RemoveSourceAppCommand.RaiseCanExecuteChanged();
        RemoveTargetAppCommand.RaiseCanExecuteChanged();
        SaveConfigCommand.RaiseCanExecuteChanged();
        TestConnectionCommand.RaiseCanExecuteChanged();
        DryRunCommand.RaiseCanExecuteChanged();
        StartMigrationCommand.RaiseCanExecuteChanged();
        GhostbusterCommand.RaiseCanExecuteChanged();
    }

    private async void RegisterSourceApp()
    {
        IsRunning = true;
        StatusMessage = "Registering Source App...";

        try
        {
            if (string.IsNullOrWhiteSpace(Config.SourceTenant.TenantId))
            {
                LogOutput("ERROR: Please enter a Source Tenant ID first.");
                return;
            }

            var result = await _appRegService.RegisterAppAsync("Source", Config.SourceTenant.TenantId, LogOutput);

            if (result.Success)
            {
                Config.SourceTenant.AppId = result.AppId ?? string.Empty;
                Config.SourceTenant.Thumbprint = result.Thumbprint ?? string.Empty;
                _configService.Save(Config);
                LoadConfiguration();
                LogOutput("Source App registered successfully.");
                LogOutput($"App ID: {result.AppId}");
                LogOutput($"Thumbprint: {result.Thumbprint}");
            }
            else
            {
                LogOutput($"ERROR: {result.Error}");
            }
        }
        catch (Exception ex)
        {
            LogOutput($"ERROR: {ex.Message}");
        }
        finally
        {
            IsRunning = false;
            StatusMessage = "Ready";
            UpdateSetupStatus();
        }
    }

    private async void RegisterTargetApp()
    {
        IsRunning = true;
        StatusMessage = "Registering Target App...";

        try
        {
            if (string.IsNullOrWhiteSpace(Config.TargetTenant.TenantId))
            {
                LogOutput("ERROR: Please enter a Target Tenant ID first.");
                return;
            }

            var result = await _appRegService.RegisterAppAsync("Target", Config.TargetTenant.TenantId, LogOutput);

            if (result.Success)
            {
                Config.TargetTenant.AppId = result.AppId ?? string.Empty;
                Config.TargetTenant.Thumbprint = result.Thumbprint ?? string.Empty;
                _configService.Save(Config);
                LoadConfiguration();
                LogOutput("Target App registered successfully.");
                LogOutput($"App ID: {result.AppId}");
                LogOutput($"Thumbprint: {result.Thumbprint}");
            }
            else
            {
                LogOutput($"ERROR: {result.Error}");
            }
        }
        catch (Exception ex)
        {
            LogOutput($"ERROR: {ex.Message}");
        }
        finally
        {
            IsRunning = false;
            StatusMessage = "Ready";
            UpdateSetupStatus();
        }
    }

    private async void RemoveSourceApp()
    {
        var result = MessageBox.Show(
            "This will remove the Source tenant app registration, certificate, and clear the configuration.\n\nAre you sure?",
            "Confirm Teardown",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.Yes) return;

        IsRunning = true;
        StatusMessage = "Removing Source App...";

        try
        {
            var teardownResult = await _teardownService.TeardownAsync("Source", LogOutput);
            if (teardownResult.Success)
            {
                LoadConfiguration();
                LogOutput("Source tenant teardown completed.");
            }
            else
            {
                LogOutput($"ERROR: {teardownResult.Error}");
            }
        }
        catch (Exception ex)
        {
            LogOutput($"ERROR: {ex.Message}");
        }
        finally
        {
            IsRunning = false;
            StatusMessage = "Ready";
            UpdateSetupStatus();
        }
    }

    private async void RemoveTargetApp()
    {
        var result = MessageBox.Show(
            "This will remove the Target tenant app registration, certificate, and clear the configuration.\n\nAre you sure?",
            "Confirm Teardown",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.Yes) return;

        IsRunning = true;
        StatusMessage = "Removing Target App...";

        try
        {
            var teardownResult = await _teardownService.TeardownAsync("Target", LogOutput);
            if (teardownResult.Success)
            {
                LoadConfiguration();
                LogOutput("Target tenant teardown completed.");
            }
            else
            {
                LogOutput($"ERROR: {teardownResult.Error}");
            }
        }
        catch (Exception ex)
        {
            LogOutput($"ERROR: {ex.Message}");
        }
        finally
        {
            IsRunning = false;
            StatusMessage = "Ready";
            UpdateSetupStatus();
        }
    }

    private async void SaveConfig()
    {
        await Task.Run(() =>
        {
            if (_configService.Save(Config))
            {
                LogOutput("Configuration saved successfully.");
                UpdateSetupStatus();
            }
            else
            {
                LogOutput("ERROR: Failed to save configuration.");
            }
        });
    }

    private async void TestConnection()
    {
        IsRunning = true;
        StatusMessage = "Testing Connections...";

        try
        {
            // Test source connection
            LogOutput("Testing Source connection...");
            var sourceResult = await _appRegService.TestConnectionAsync(
                Config.Migration.SourceSiteUrl,
                Config.SourceTenant.AppId,
                Config.SourceTenant.Thumbprint,
                Config.SourceTenant.TenantId,
                LogOutput);

            LogOutput(sourceResult ? "Source connection: SUCCESS" : "Source connection: FAILED");

            // Test target connection
            LogOutput("Testing Target connection...");
            var targetResult = await _appRegService.TestConnectionAsync(
                Config.Migration.TargetSiteUrl,
                Config.TargetTenant.AppId,
                Config.TargetTenant.Thumbprint,
                Config.TargetTenant.TenantId,
                LogOutput);

            LogOutput(targetResult ? "Target connection: SUCCESS" : "Target connection: FAILED");
        }
        catch (Exception ex)
        {
            LogOutput($"ERROR: {ex.Message}");
        }
        finally
        {
            IsRunning = false;
            StatusMessage = "Ready";
        }
    }

    private void DryRun()
    {
        OpenOperationWindow(OperationType.DryRun);
    }

    private void StartMigration()
    {
        OpenOperationWindow(OperationType.Migration);
    }

    private void Ghostbuster()
    {
        OpenOperationWindow(OperationType.Ghostbuster);
    }

    private void OpenOperationWindow(OperationType operationType)
    {
        var viewModel = new OperationWindowViewModel(_migrationService, Config, operationType);
        var window = new OperationWindow(viewModel)
        {
            Owner = System.Windows.Application.Current.MainWindow
        };
        window.ShowDialog();
    }

    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

/// <summary>
/// Simple relay command implementation
/// </summary>
public class RelayCommand : ICommand
{
    private readonly Action _execute;
    private readonly Func<bool>? _canExecute;

    public event EventHandler? CanExecuteChanged;

    public RelayCommand(Action execute, Func<bool>? canExecute = null)
    {
        _execute = execute ?? throw new ArgumentNullException(nameof(execute));
        _canExecute = canExecute;
    }

    public bool CanExecute(object? parameter) => _canExecute?.Invoke() ?? true;

    public void Execute(object? parameter) => _execute();

    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}