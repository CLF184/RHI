using Microsoft.UI.Xaml.Controls;
using RenoDXCommander.Services;

namespace RenoDXCommander;

/// <summary>
/// Settings-page language selector. Kept in its own partial so upstream
/// SettingsHandler changes merge cleanly.
/// </summary>
public partial class SettingsHandler
{
    private bool _syncingLanguageCombo;

    public void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingLanguageCombo)
            return;

        if (sender is not ComboBox combo || combo.SelectedItem is not ComboBoxItem item)
            return;

        var preference = item.Tag as string;
        if (string.IsNullOrWhiteSpace(preference))
            return;

        var normalized = LocalizationService.NormalizePreference(preference);
        if (string.Equals(ViewModel.Settings.Language, normalized, StringComparison.OrdinalIgnoreCase))
            return;

        ViewModel.Settings.Language = normalized;
        ViewModel.SaveSettingsPublic();
    }

    private void SyncLanguageCombo()
    {
        _syncingLanguageCombo = true;
        try
        {
            var current = LocalizationService.NormalizePreference(ViewModel.Settings.Language);
            for (var i = 0; i < _window.LanguageCombo.Items.Count; i++)
            {
                if (_window.LanguageCombo.Items[i] is ComboBoxItem item
                    && item.Tag is string tag
                    && string.Equals(LocalizationService.NormalizePreference(tag), current, StringComparison.OrdinalIgnoreCase))
                {
                    _window.LanguageCombo.SelectedIndex = i;
                    return;
                }
            }

            _window.LanguageCombo.SelectedIndex = 0;
        }
        finally
        {
            _syncingLanguageCombo = false;
        }
    }
}
