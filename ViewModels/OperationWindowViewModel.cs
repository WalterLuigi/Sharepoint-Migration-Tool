using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;
using SharePointMigrationTool.Models;
using SharePointMigrationTool.Services;

namespace SharePointMigrationTool.ViewModels;

/// <summary>
/// View model for the operation window with preview and confirmation
/// </summary>
public class OperationWindowViewModel : INotifyPropertyChanged
{
    private readonly MigrationService _migrationService;
    private readonly MigrationConfig _config;
    private readonly OperationType _operationType;

    private string _windowTitle = "Operation";
    private string _headerText = "Processing...";
    private string _outputLog = string.Empty;
    private string _statusMessage = "Loading preview...";
    private int _folderCount;
    private int _fileCount;
    private List<string> _sampleFiles = new();
    private bool _isRunning = true;
    private bool _operationComplete;
    private Visibility _previewVisibility = Visibility.Visible;
    private Visibility _proceedVisibility = Visibility.Visible;
    private Visibility _closeVisibility = Visibility.Collapsed;

    public event PropertyChangedEventHandler? PropertyChanged;
    public Action? CloseAction { get; set; }

    public string WindowTitle
    {
        get => _windowTitle;
        set { _windowTitle = value; OnPropertyChanged(); }
    }

    public string HeaderText
    {
        get => _headerText;
        set { _headerText = value; OnPropertyChanged(); }
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

    public int FolderCount
    {
        get => _folderCount;
        set { _folderCount = value; OnPropertyChanged(); }
    }

    public int FileCount
    {
        get => _fileCount;
        set { _fileCount = value; OnPropertyChanged(); }
    }

    public List<string> SampleFiles
    {
        get => _sampleFiles;
        set { _sampleFiles = value; OnPropertyChanged(); }
    }

    public bool IsRunning
    {
        get => _isRunning;
        set
        {
            _isRunning = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanProceed));
            ProceedCommand.RaiseCanExecuteChanged();
        }
    }

    public bool CanProceed => !IsRunning && !_operationComplete && FileCount > 0;

    public Visibility PreviewVisibility
    {
        get => _previewVisibility;
        set { _previewVisibility = value; OnPropertyChanged(); }
    }

    public Visibility ProceedVisibility
    {
        get => _proceedVisibility;
        set { _proceedVisibility = value; OnPropertyChanged(); }
    }

    public Visibility CloseVisibility
    {
        get => _closeVisibility;
        set { _closeVisibility = value; OnPropertyChanged(); }
    }

    public RelayCommand ProceedCommand { get; }
    public RelayCommand CancelCommand { get; }
    public RelayCommand CloseCommand { get; }
    public RelayCommand ClearLogCommand { get; }
    public RelayCommand ExportLogCommand { get; }

    public OperationWindowViewModel(MigrationService migrationService, MigrationConfig config, OperationType operationType)
    {
        _migrationService = migrationService;
        _config = config;
        _operationType = operationType;

        ProceedCommand = new RelayCommand(Proceed, () => CanProceed);
        CancelCommand = new RelayCommand(Cancel);
        CloseCommand = new RelayCommand(Close);
        ClearLogCommand = new RelayCommand(ClearLog);
        ExportLogCommand = new RelayCommand(ExportLog);

        InitializeWindow();
    }

    private void InitializeWindow()
    {
        switch (_operationType)
        {
            case OperationType.DryRun:
                WindowTitle = "Dry Run Analysis";
                HeaderText = "Analyzing differences between source and target...";
                break;
            case OperationType.Migration:
                WindowTitle = "Migration Preview";
                HeaderText = "Review files to be migrated:";
                break;
            case OperationType.Ghostbuster:
                WindowTitle = "Ghostbuster Preview";
                HeaderText = "Review files to be checked in:";
                break;
        }

        _ = LoadPreviewAsync();
    }

    private async Task LoadPreviewAsync()
    {
        try
        {
            StatusMessage = "Loading preview...";

            // For Ghostbuster, we run interactively - skip preview and run full script
            if (_operationType == OperationType.Ghostbuster)
            {
                WindowTitle = "Ghostbuster";
                HeaderText = "Checking in checked-out files...";
                PreviewVisibility = Visibility.Collapsed;
                ProceedVisibility = Visibility.Collapsed;
                StatusMessage = "Running Ghostbuster in separate window...";
                LogOutput("A PowerShell window will open for authentication.");
                LogOutput("Please sign in and follow the prompts in that window.");
                LogOutput("");

                var result = await _migrationService.ExecuteGhostbusterAsync(_config, LogOutput);
                StatusMessage = result.Success
                    ? "Ghostbuster complete"
                    : $"Ghostbuster failed: {result.Error}";

                _operationComplete = true;
                CloseVisibility = Visibility.Visible;
                IsRunning = false;
                return;
            }

            var previewResult = await _migrationService.GetPreviewAsync(
                _config,
                _operationType,
                LogOutput);

            FolderCount = previewResult.FolderCount;
            FileCount = previewResult.FileCount;
            SampleFiles = previewResult.SampleItems;

            StatusMessage = $"Found {FolderCount} folders and {FileCount} files";

            if (FileCount == 0 && FolderCount == 0)
            {
                LogOutput("No differences found. Source and target are in sync.");
                StatusMessage = "No changes needed";
                ShowCompletionState();
            }
        }
        catch (Exception ex)
        {
            LogOutput($"Error loading preview: {ex.Message}");
            StatusMessage = "Preview failed";
            ShowCompletionState();
        }
        finally
        {
            IsRunning = false;
        }
    }

    private async void Proceed()
    {
        if (_operationType == OperationType.DryRun)
        {
            LogOutput("Dry run complete. No action taken.");
            StatusMessage = "Dry run complete";
            ShowCompletionState();
            return;
        }

        IsRunning = true;
        ProceedVisibility = Visibility.Collapsed;
        PreviewVisibility = Visibility.Collapsed;
        StatusMessage = _operationType == OperationType.Migration
            ? "Running migration..."
            : "Running ghostbuster...";

        try
        {
            if (_operationType == OperationType.Migration)
            {
                var result = await _migrationService.ExecuteMigrationAsync(_config, LogOutput);
                StatusMessage = result.Success
                    ? $"Migration complete. {result.FilesMigrated} files, {result.FoldersCreated} folders"
                    : $"Migration failed: {result.Error}";
            }
            else if (_operationType == OperationType.Ghostbuster)
            {
                var result = await _migrationService.ExecuteGhostbusterAsync(_config, LogOutput);
                StatusMessage = result.Success
                    ? "Ghostbuster complete"
                    : $"Ghostbuster failed: {result.Error}";
            }
        }
        catch (Exception ex)
        {
            LogOutput($"Error: {ex.Message}");
            StatusMessage = "Operation failed";
        }
        finally
        {
            IsRunning = false;
            _operationComplete = true;
            ShowCompletionState();
        }
    }

    private void Cancel()
    {
        if (!_operationComplete && _operationType != OperationType.DryRun)
        {
            LogOutput("Operation cancelled by user.");
        }
        CloseAction?.Invoke();
    }

    private void Close()
    {
        CloseAction?.Invoke();
    }

    private void ShowCompletionState()
    {
        _operationComplete = true;
        ProceedVisibility = Visibility.Collapsed;
        CloseVisibility = Visibility.Visible;
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
            FileName = $"{_operationType}_log_{DateTime.Now:yyyyMMdd_HHmmss}.txt"
        };

        if (saveDialog.ShowDialog() == true)
        {
            try
            {
                var header = $"SharePoint Migration Tool - {_operationType} Log{Environment.NewLine}" +
                            $"Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}{Environment.NewLine}" +
                            $"Source: {_config.Migration.SourceSiteUrl}{Environment.NewLine}" +
                            $"Target: {_config.Migration.TargetSiteUrl}{Environment.NewLine}" +
                            $"Library: {_config.Migration.LibraryName}{Environment.NewLine}" +
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

    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}