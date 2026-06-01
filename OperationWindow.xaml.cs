using System.Windows;

namespace SharePointMigrationTool;

/// <summary>
/// Secondary window for long-running operations with preview and confirmation
/// </summary>
public partial class OperationWindow : Window
{
    public OperationWindow()
    {
        InitializeComponent();
    }

    /// <summary>
    /// Create operation window with view model
    /// </summary>
    public OperationWindow(ViewModels.OperationWindowViewModel viewModel) : this()
    {
        DataContext = viewModel;
        viewModel.CloseAction = () => Close();
    }
}