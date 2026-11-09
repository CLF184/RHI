using System.Diagnostics;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RenoDXCommander.Services;

/// <summary>
/// Checks GitHub Releases for a newer version of RHI and downloads the installer if requested.
/// </summary>
public class UpdateService : IUpdateService
{
    private readonly HttpClient _http;
    private readonly GitHubETagCache _etagCache;

    public UpdateService(HttpClient http, GitHubETagCache etagCache)
    {
        _http = http;
        _etagCache = etagCache;
    }
    // zh-CN fork: check the Chinese releases instead of upstream. Versioned
    // releases are published as normal releases (the rolling zhCN-latest dev
    // build is a prerelease), so /releases/latest always points at a Chinese
    // version number.
    private const string LatestReleaseApiUrl =
        "https://api.github.com/repos/CLF184/RHI/releases/latest";

    // The asset filenames to look for when downloading. Only used as a
    // fallback name by DownloadInstallerAsync — the update UI opens the
    // release page for the portable zip instead of running an installer.
    private static readonly string[] InstallerFileNames = ["RHI-zhCN.zip"];

    /// <summary>
    /// Returns the current app version from the assembly metadata (set via .csproj AssemblyVersion).
    /// </summary>
    public Version CurrentVersion =>
        Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0, 0);

    /// <summary>
    /// Silently checks CLF184/RHI for a newer Chinese release. Returns the parsed
    /// remote version, the portable zip URL and the release page URL, or null if
    /// no update is available or the check fails.
    /// </summary>
    public async Task<UpdateInfo?> CheckForUpdateAsync(bool betaOptIn = false)
    {
        // zh-CN fork: check CLF184/RHI (the Chinese releases), not upstream.
        // The release asset is a portable zip, so the update dialog opens the
        // release page instead of trying to run an installer over this build.
        try
        {
            var release = await FetchReleaseAsync(LatestReleaseApiUrl).ConfigureAwait(false);
            if (release == null)
            {
                CrashReporter.Log("[UpdateService.CheckForUpdateAsync] No zh-CN release found");
                return null;
            }

            var current = CurrentVersion;
            var currentRdxc = new RdxcVersion(current.Major, current.Minor, current.Build,
                current.Revision > 0 ? current.Revision : null);
            var remote = release.Version;

            if (remote.Major < currentRdxc.Major
                || (remote.Major == currentRdxc.Major && remote.Minor < currentRdxc.Minor)
                || (remote.Major == currentRdxc.Major && remote.Minor == currentRdxc.Minor && remote.Build <= currentRdxc.Build))
            {
                CrashReporter.Log($"[UpdateService.CheckForUpdateAsync] Up to date (local={currentRdxc.ToDisplayString()}, remote={remote.ToDisplayString()})");
                return null;
            }

            CrashReporter.Log($"[UpdateService.CheckForUpdateAsync] Update available {currentRdxc.ToDisplayString()} → {remote.ToDisplayString()} ({release.PageUrl})");
            return new UpdateInfo
            {
                CurrentVersion = new Version(current.Major, current.Minor, current.Build),
                RemoteVersion  = new Version(remote.Major, remote.Minor, remote.Build),
                DownloadUrl    = release.DownloadUrl,
                DisplayVersion = remote.ToDisplayString(),
                ReleasePageUrl = release.PageUrl,
                IsPortableZip  = true,
            };
        }
        catch (Exception ex)
        {
            // Update check should never crash the app — swallow and log
            CrashReporter.Log($"[UpdateService.CheckForUpdateAsync] Check failed — {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Fetches the latest zh-CN release, parses its version, and extracts the
    /// portable zip asset URL and the release page URL.
    /// </summary>
    private async Task<ForkRelease?> FetchReleaseAsync(string apiUrl)
    {
        var json = await _etagCache.GetWithETagAsync(_http, apiUrl, $"RHI-zhCN/{CurrentVersion}").ConfigureAwait(false);
        if (json == null)
        {
            CrashReporter.Log($"[UpdateService.FetchReleaseAsync] GitHub API returned error for {apiUrl}");
            return null;
        }

        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        // Parse version from release name or tag_name using RdxcVersion
        var releaseName = root.TryGetProperty("name", out var name) ? name.GetString() : null;
        var tagName = root.TryGetProperty("tag_name", out var tag) ? tag.GetString() : null;

        if (!RdxcVersion.TryParse(releaseName, out var version) &&
            !RdxcVersion.TryParse(tagName, out version))
        {
            CrashReporter.Log($"[UpdateService.FetchReleaseAsync] Could not parse version from tag='{tagName}' name='{releaseName}'");
            return null;
        }

        // The Chinese release ships RHI-zhCN-<version>-win-x64.zip.
        string? downloadUrl = null;
        if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
        {
            foreach (var asset in assets.EnumerateArray())
            {
                var assetName = asset.TryGetProperty("name", out var n) ? n.GetString() : null;
                if (!string.IsNullOrEmpty(assetName)
                    && assetName.StartsWith("RHI-zhCN-", StringComparison.OrdinalIgnoreCase)
                    && assetName.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                {
                    downloadUrl = asset.TryGetProperty("browser_download_url", out var url)
                        ? url.GetString() : null;
                    if (!string.IsNullOrEmpty(downloadUrl)) break;
                }
            }
        }

        if (string.IsNullOrEmpty(downloadUrl))
        {
            CrashReporter.Log($"[UpdateService.FetchReleaseAsync] Version {version.ToDisplayString()} found but no RHI-zhCN-*.zip asset");
            return null;
        }

        var pageUrl = root.TryGetProperty("html_url", out var html) ? html.GetString() : null;
        if (string.IsNullOrEmpty(pageUrl))
            pageUrl = $"https://github.com/CLF184/RHI/releases/tag/{tagName}";

        return new ForkRelease(version, downloadUrl, pageUrl);
    }

    private sealed record ForkRelease(RdxcVersion Version, string DownloadUrl, string PageUrl);

    /// <summary>
    /// Downloads the installer to a temp file and returns the file path.
    /// Reports progress via the optional callback.
    /// </summary>
    public async Task<string?> DownloadInstallerAsync(
        string downloadUrl,
        IProgress<(string msg, double pct)>? progress = null,
        CancellationToken cancellationToken = default)
    {
        string? tempPath = null;
        try
        {
            // HttpClient.Timeout ends at the headers with ResponseHeadersRead.
            // Apply a deadline to the body reads/writes as well as shutdown cancellation.
            using var transfer = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            transfer.CancelAfter(TimeSpan.FromMinutes(10));
            var token = transfer.Token;
            progress?.Report(("Downloading update...", 0));

            using var request = new HttpRequestMessage(HttpMethod.Get, downloadUrl);
            request.Headers.UserAgent.Add(new ProductInfoHeaderValue("RHI", CurrentVersion.ToString()));

            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token)
                .ConfigureAwait(false);
            response.EnsureSuccessStatusCode();

            var totalBytes = response.Content.Headers.ContentLength ?? -1;
            // Derive the installer filename from the download URL, falling back to RHI-Setup.exe
            var fileName = Path.GetFileName(new Uri(downloadUrl).LocalPath);
            if (string.IsNullOrEmpty(fileName)) fileName = InstallerFileNames[0];
            tempPath = Path.Combine(Path.GetTempPath(), fileName);

            await using var contentStream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
            await using var fileStream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None,
                bufferSize: 1024 * 1024, useAsync: true);

            var buffer = new byte[1024 * 1024]; // 1 MB
            long totalRead = 0;
            int bytesRead;

            while ((bytesRead = await contentStream.ReadAsync(buffer, token).ConfigureAwait(false)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead), token).ConfigureAwait(false);
                totalRead += bytesRead;

                if (totalBytes > 0)
                {
                    var pct = (double)totalRead / totalBytes * 100;
                    progress?.Report(($"Downloading update... {pct:F0}%", pct));
                }
            }

            if (totalBytes >= 0 && totalRead != totalBytes)
                throw new IOException($"Incomplete installer download: expected {totalBytes} bytes, received {totalRead}.");
            progress?.Report(("Download complete.", 100));
            CrashReporter.Log($"[UpdateService.DownloadInstallerAsync] Downloaded installer to {tempPath} ({totalRead:N0} bytes)");
            return tempPath;
        }
        catch (Exception ex)
        {
            CrashReporter.Log($"[UpdateService.DownloadInstallerAsync] Download failed — {ex.Message}");
            if (tempPath != null)
            {
                try { File.Delete(tempPath); }
                catch (Exception cleanupError) { CrashReporter.Log($"[UpdateService] Partial download cleanup failed — {cleanupError.Message}"); }
            }
            progress?.Report(($"Download failed: {ex.Message}", 0));
            return null;
        }
    }

    /// <summary>
    /// Launches the downloaded installer and requests the app to close.
    /// </summary>
    public void LaunchInstallerAndExit(string installerPath, Action closeApp)
    {
        try
        {
            CrashReporter.Log($"[UpdateService.LaunchInstaller] Launching installer {installerPath}");
            Process.Start(new ProcessStartInfo
            {
                FileName        = installerPath,
                UseShellExecute = true,
            });

            // Give the installer a moment to start, then close the app
            closeApp();
        }
        catch (Exception ex)
        {
            CrashReporter.Log($"[UpdateService.LaunchInstaller] Failed to launch installer — {ex.Message}");
        }
    }
}

/// <summary>
/// Contains information about an available update.
/// </summary>
public class UpdateInfo
{
    public required Version CurrentVersion { get; init; }
    public required Version RemoteVersion  { get; init; }
    public required string  DownloadUrl    { get; init; }
    public string? DisplayVersion { get; init; }

    /// <summary>zh-CN fork: release page to open instead of running an installer.</summary>
    public string? ReleasePageUrl { get; init; }

    /// <summary>zh-CN fork: the release ships a portable zip, not an installer.</summary>
    public bool IsPortableZip { get; init; }
}

/// <summary>
/// Represents a RHI version with optional beta suffix.
/// Examples: "1.4.8", "1.4.8-beta1", "1.4.8 beta 1"
/// </summary>
public readonly record struct RdxcVersion(int Major, int Minor, int Build, int? BetaNumber = null)
    : IComparable<RdxcVersion>
{
    /// <summary>True when this version has a beta suffix.</summary>
    public bool IsBeta => BetaNumber.HasValue;

    /// <summary>Base version tuple without beta suffix, used for priority comparison.</summary>
    public (int, int, int) BaseVersion => (Major, Minor, Build);

    /// <summary>
    /// Compares by (Major, Minor, Build) first, then by beta status:
    /// stable (no beta) is greater than any beta at the same base version,
    /// and a higher beta number is greater than a lower one.
    /// </summary>
    public int CompareTo(RdxcVersion other)
    {
        int cmp = Major.CompareTo(other.Major);
        if (cmp != 0) return cmp;

        cmp = Minor.CompareTo(other.Minor);
        if (cmp != 0) return cmp;

        cmp = Build.CompareTo(other.Build);
        if (cmp != 0) return cmp;

        // Same base version — stable > beta, higher beta > lower beta
        if (!IsBeta && !other.IsBeta) return 0;
        if (!IsBeta && other.IsBeta) return 1;   // stable > beta
        if (IsBeta && !other.IsBeta) return -1;  // beta < stable

        // Both are beta — compare beta numbers
        return BetaNumber!.Value.CompareTo(other.BetaNumber!.Value);
    }

    // Regex: optional leading text (e.g. "HDRX-", "v"), then Major.Minor.Build, optional beta suffix
    private static readonly Regex VersionPattern = new(
        @"(\d+)\.(\d+)\.(\d+)(?:[\s-]*beta[\s-]*(\d+))?",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>
    /// Parses version strings such as "1.4.8", "1.4.8-beta1", "1.4.8 beta 1",
    /// "v1.4.8-beta2", "RHI-1.4.8-beta1". Returns false and logs when input is invalid.
    /// </summary>
    public static bool TryParse(string? input, out RdxcVersion version)
    {
        version = default;

        if (string.IsNullOrWhiteSpace(input))
        {
            CrashReporter.Log($"[RdxcVersion.TryParse] Cannot parse null or empty version string");
            return false;
        }

        var match = VersionPattern.Match(input);
        if (!match.Success)
        {
            CrashReporter.Log($"[RdxcVersion.TryParse] Cannot parse version from '{input}'");
            return false;
        }

        int major = int.Parse(match.Groups[1].Value);
        int minor = int.Parse(match.Groups[2].Value);
        int build = int.Parse(match.Groups[3].Value);
        int? betaNumber = match.Groups[4].Success ? int.Parse(match.Groups[4].Value) : null;

        version = new RdxcVersion(major, minor, build, betaNumber);
        return true;
    }

    /// <summary>
    /// Formats to display string: "1.4.8" for stable, "1.4.8 beta 1" for beta.
    /// </summary>
    public string ToDisplayString() =>
        IsBeta ? $"{Major}.{Minor}.{Build} beta {BetaNumber}" : $"{Major}.{Minor}.{Build}";
}

/// <summary>
/// Determines which update (if any) to offer based on current version,
/// latest stable, and latest beta.
/// </summary>
internal static class VersionResolver
{
    /// <summary>
    /// Returns the version to offer, or null if up to date.
    /// Rules:
    ///   - Stable always wins over beta at same or higher base version
    ///   - Beta only offered when its base version exceeds both latest stable's
    ///     and current version's base version
    ///   - Only offer if candidate's base version > current base version
    /// </summary>
    public static RdxcVersion? Resolve(
        RdxcVersion current,
        RdxcVersion? latestStable,
        RdxcVersion? latestBeta)
    {
        var currentBase = current.BaseVersion;

        // Determine if stable is a valid candidate (base version > current base version)
        bool stableValid = latestStable.HasValue
            && latestStable.Value.BaseVersion.CompareTo(currentBase) > 0;

        // Determine if beta is a valid candidate:
        //   - base version > current base version, OR
        //   - same base version but current is a beta with a lower beta number
        //   - base version > latest stable base version (beta only wins when ahead of stable)
        bool betaValid = latestBeta.HasValue
            && (latestBeta.Value.BaseVersion.CompareTo(currentBase) > 0
                || (latestBeta.Value.BaseVersion == currentBase
                    && current.IsBeta
                    && latestBeta.Value.CompareTo(current) > 0))
            && (!latestStable.HasValue
                || latestBeta.Value.BaseVersion.CompareTo(latestStable.Value.BaseVersion) > 0);

        // Beta takes priority when it's ahead of both stable and current
        if (betaValid)
            return latestBeta;

        if (stableValid)
            return latestStable;

        return null;
    }
}
