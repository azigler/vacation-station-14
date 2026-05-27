using System.Linq;
using Content.Client.Administration.UI;
using Content.Client.Administration.UI.CustomControls;
using Content.Client.Administration.UI.Logs;
using Content.Client.UserInterface.Controls;
using Content.Client.UserInterface.Systems.MenuBar.Widgets;
using Content.IntegrationTests.Tests.Interaction;
using Content.Server.Administration.Commands;
using Content.Server.Administration.Logs;
using Content.Shared.Database;

namespace Content.IntegrationTests.Tests.Administration.Logs;

public sealed class LogWindowTest : InteractionTest
{
    protected override PoolSettings Settings => new() { Connected = true, Dirty = true, AdminLogsEnabled = true, DummyTicker = false };

    [Test]
    public async Task TestAdminLogsWindow()
    {
        // First, generate a new log
        var log = Server.Resolve<IAdminLogManager>();
        var guid = Guid.NewGuid();
        await Server.WaitPost(() => log.Add(LogType.Unknown, $"{SPlayer} test log 1: {guid}"));

        // Click the admin button in the menu bar
        await ClickWidgetControl<GameTopMenuBar, MenuButton>(nameof(GameTopMenuBar.AdminButton));
        var adminWindow = GetWindow<AdminMenuWindow>();

        // Find and click the "open logs" button.
        Assert.That(TryGetControlFromChildren<CommandButton>(x => x.Command == OpenAdminLogsCommand.Cmd, adminWindow, out var btn));
        await ClickControl(btn!);
        var logWindow = GetWindow<AdminLogsWindow>();

        // Find the log search field and refresh buttons
        var search = logWindow.Logs.LogSearch;
        var refresh = logWindow.Logs.RefreshButton;
        var cont = logWindow.Logs.LogsContainer;

        // Search for the log we added earlier.
        await Client.WaitPost(() => search.Text = guid.ToString());
        await ClickControl(refresh);
        var searchResult = await WaitForLogSearchResult(cont); // VS - poll until result appears (upstream `await RunTicks(5)` was insufficient under CI thread-pool contention; flake fix)
        Assert.That(searchResult.Length, Is.EqualTo(1));
        Assert.That(searchResult[0].Log.Message, Contains.Substring($" test log 1: {guid}"));

        // Add a new log
        guid = Guid.NewGuid();
        await Server.WaitPost(() => log.Add(LogType.Unknown, $"{SPlayer} test log 2: {guid}"));

        // Update the search and refresh
        await Client.WaitPost(() => search.Text = guid.ToString());
        await ClickControl(refresh);
        // VS - poll until the new result appears AND the old one (test log 1) is gone.
        // Just polling for ≥1 result can return the stale "test log 1" before the refresh completes.
        searchResult = await WaitForLogSearchResult(cont, expectMessageContaining: $" test log 2: {guid}");
        Assert.That(searchResult.Length, Is.EqualTo(1));
        Assert.That(searchResult[0].Log.Message, Contains.Substring($" test log 2: {guid}"));
    }

    // VS - flake-fix helper: poll for the admin-log search result. Upstream uses
    // a fixed `RunTicks(5)` (~166ms at 30Hz), which is insufficient under CI
    // thread-pool contention — the refresh button kicks an async DB query +
    // UI repopulate and 166ms is a tight budget. Polls every tick up to 90
    // ticks (~3s) and returns the moment the expected shape appears.
    private async Task<AdminLogLabel[]> WaitForLogSearchResult(
        Robust.Client.UserInterface.Control cont,
        string? expectMessageContaining = null)
    {
        AdminLogLabel[] result = System.Array.Empty<AdminLogLabel>();
        for (var t = 0; t < 90; t++)
        {
            await RunTicks(1);
            result = cont.Children.Where(x => x.Visible && x is AdminLogLabel).Cast<AdminLogLabel>().ToArray();
            if (result.Length != 1) continue;
            if (expectMessageContaining is null || result[0].Log.Message.Contains(expectMessageContaining))
                return result;
        }
        return result;
    }
}
