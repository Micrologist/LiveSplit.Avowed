state("Avowed-WinGDK-Shipping"){}
state("Avowed-Win64-Shipping"){}

startup
{
    vars.Log = (Action<object>)((output) => print("[Avowed ASL] " + output));

    if (timer.CurrentTimingMethod == TimingMethod.RealTime)
    {
        DialogResult dbox = MessageBox.Show(timer.Form,
            "Avowed uses load removed time.\nWould you like to switch LiveSplit's timing method to that?",
            "LiveSplit | Avowed ASL",
            MessageBoxButtons.YesNo);

        if (dbox == DialogResult.Yes)
        {
            timer.CurrentTimingMethod = TimingMethod.GameTime;
        }
    }

    settings.Add("VelocityOutput", false, "Output Horizontal Velocity");
    vars.SetTextComponent = (Action<string, string>)((id, text) =>
	{
	    var textSettings = timer.Layout.Components.Where(x => x.GetType().Name == "TextComponent").Select(x => x.GetType().GetProperty("Settings").GetValue(x, null));
	    var textSetting = textSettings.FirstOrDefault(x => (x.GetType().GetProperty("Text1").GetValue(x, null) as string) == id);
	    if (textSetting == null)
	    {
	        var textComponentAssembly = Assembly.LoadFrom("Components\\LiveSplit.Text.dll");
	        var textComponent = Activator.CreateInstance(textComponentAssembly.GetType("LiveSplit.UI.Components.TextComponent"), timer);
	        timer.Layout.LayoutComponents.Add(new LiveSplit.UI.Components.LayoutComponent("LiveSplit.Text.dll", textComponent as LiveSplit.UI.Components.IComponent));
	
	        textSetting = textComponent.GetType().GetProperty("Settings", BindingFlags.Instance | BindingFlags.Public).GetValue(textComponent, null);
	        textSetting.GetType().GetProperty("Text1").SetValue(textSetting, id);
	    }
	
	    if (textSetting != null) {
            textSetting.GetType().GetProperty("Text2").SetValue(textSetting, text);
        }
    });
}

init
{
    var scn = new SignatureScanner(game, game.MainModule.BaseAddress, game.MainModule.ModuleMemorySize);
    var syncLoadTrg = new SigScanTarget(5, "89 43 60 8B 05") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var syncLoadCounter = scn.Scan(syncLoadTrg);
    var localPlayerTrg = new SigScanTarget(3, "48 89 35 ?? ?? ?? ?? 0F 10 0D") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var localPlayer = scn.Scan(localPlayerTrg);
    var namePoolTrg = new SigScanTarget(7, "8B D9 74 ?? 48 8D 15 ?? ?? ?? ?? EB") { OnFound = (p, s, ptr) => ptr + 0x4 + game.ReadValue<int>(ptr) };
    var namePool = scn.Scan(namePoolTrg);

    if(syncLoadCounter == IntPtr.Zero || localPlayer == IntPtr.Zero || namePool == IntPtr.Zero)
    {
        throw new Exception("One or more base pointers not found - retrying");
    }

    vars.Log("Sync Load Counter: 0x"+syncLoadCounter.ToString("X8"));
    vars.Log("Local Player: 0x"+localPlayer.ToString("X8"));
    vars.Log("Name Pool: 0x"+namePool.ToString("X8"));

    vars.FNameToString = (Func<ulong, string>)(fName =>
    {
        var number   = (fName & 0xFFFFFFFF00000000) >> 0x20;
        var chunkIdx = (fName & 0x00000000FFFF0000) >> 0x10;
        var nameIdx  = (fName & 0x000000000000FFFF) >> 0x00;
        var chunk = game.ReadPointer(namePool + 0x10 + (int)chunkIdx * 0x8);
        var nameEntry = chunk + (int)nameIdx * 0x2;
        var length = game.ReadValue<short>(nameEntry) >> 6;
        var name = game.ReadString(nameEntry + 0x2, length);
        return number == 0 ? name : name + "_" + number;
    });

    vars.Watchers = new MemoryWatcherList
    {
        new MemoryWatcher<int>(new DeepPointer(syncLoadCounter)) { Name = "syncLoadCount" },
        new MemoryWatcher<IntPtr>(new DeepPointer(localPlayer, 0x78, 0x80, 0x220)) { Name = "loadingWidget"},
        new MemoryWatcher<ulong>(new DeepPointer(localPlayer, 0x78, 0x78, 0x18)) { Name = "worldFName"},
        new MemoryWatcher<double>(new DeepPointer(localPlayer, 0x30, 0x2E8, 0x328, 0xB8)) { Name = "xVel"},
        new MemoryWatcher<double>(new DeepPointer(localPlayer, 0x30, 0x2E8, 0x328, 0xC0)) { Name = "yVel"},
        //new MemoryWatcher<double>(new DeepPointer(localPlayer, 0x30, 0x2E8, 0x328, 0xC8)) { Name = "zVel"},
    };

    vars.Watchers.UpdateAll(game);
    var worldFName = (ulong)vars.Watchers["worldFName"].Current;
    current.world = old.world = vars.FNameToString(worldFName);
    vars.startAfterLoad = false;
}

update
{
    vars.Watchers.UpdateAll(game);

    var worldFName = (ulong)vars.Watchers["worldFName"].Current;
    current.world = worldFName != 0x0 ? vars.FNameToString(worldFName) : old.world;

    var showingLoadingscreen = (vars.Watchers["loadingWidget"].Current != IntPtr.Zero) && current.world != "MainMenu";
    var isSyncLoading = vars.Watchers["syncLoadCount"].Current > 0;
    current.loading = isSyncLoading || showingLoadingscreen;

    if(settings["VelocityOutput"]) {
        var xVel = (double)vars.Watchers["xVel"].Current;
        var yVel = (double)vars.Watchers["yVel"].Current;
        //var zVel = (double)vars.Watchers["zVel"].Current;
        double hVel = Math.Floor(Math.Sqrt(xVel * xVel + yVel * yVel) + 0.5f) / 100;
        vars.SetTextComponent("Horizontal Velocity:", hVel.ToString());
    }
}

isLoading
{
    return current.loading;
}

start
{
    if(current.world == "ADR_07_PRO" && old.world == "MainMenu")
    {
        vars.startAfterLoad = true;
    }

    if(vars.startAfterLoad && !current.loading)
    {
        return true;
    }
}
onStart
{
    timer.IsGameTimePaused = current.loading;
    vars.startAfterLoad = false;
}

exit
{
    timer.IsGameTimePaused = true;
}
