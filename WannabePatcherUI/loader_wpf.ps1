Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# --- Step 1: Define XAML UI ---
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WannabePatcher" Height="450" Width="600"
        Background="#1e1e1e" Foreground="White" WindowStartupLocation="CenterScreen">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <TextBlock Text="WannabePatcher" FontSize="26" FontWeight="SemiBold" Margin="0,0,0,20" Grid.Row="0" Foreground="#007acc"/>
        
        <!-- Input Area -->
        <StackPanel Orientation="Horizontal" Grid.Row="1" Margin="0,0,0,15">
            <TextBlock Text="AppID:" VerticalAlignment="Center" Margin="0,0,10,0" FontSize="14"/>
            <ComboBox x:Name="AppIdCombo" Width="180" IsEditable="True" Background="#2d2d30" Foreground="Black" FontSize="14" ToolTip="Enter or select a Steam AppID"/>
            
            <Button x:Name="StartButton" Content="Start Patch" Width="100" Margin="15,0,0,0"
                    Background="#007acc" Foreground="White" BorderThickness="0" Cursor="Hand" FontWeight="Bold"/>
                    
            <Button x:Name="ClearLogButton" Content="Clear Log" Width="80" Margin="10,0,0,0"
                    Background="#3f3f46" Foreground="White" BorderThickness="0" Cursor="Hand"/>
        </StackPanel>
        
        <!-- Log Header -->
        <TextBlock Text="Activity Log:" Margin="0,0,0,5" Grid.Row="2" Foreground="#888888"/>
        
        <!-- Log Output Box -->
        <TextBox x:Name="LogTextBox" Grid.Row="3" Background="#252526" Foreground="#d4d4d4"
                 BorderBrush="#3e3e42" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 TextWrapping="NoWrap" FontFamily="Consolas" FontSize="13" Padding="5"/>
    </Grid>
</Window>
"@

# Parse XAML
$reader = (New-Object System.Xml.XmlNodeReader([xml]$xaml))
$Window = [System.Windows.Markup.XamlReader]::Load($reader)

# Find UI Elements
$AppIdCombo = $Window.FindName("AppIdCombo")
$StartButton = $Window.FindName("StartButton")
$ClearLogButton = $Window.FindName("ClearLogButton")
$LogTextBox = $Window.FindName("LogTextBox")
$Dispatcher = $Window.Dispatcher

# --- Fetch Supported AppIDs from API ---
$apiRunspace = [runspacefactory]::CreateRunspace()
$apiRunspace.ApartmentState = "STA"
$apiRunspace.Open()

$apiPs = [PowerShell]::Create()
$apiPs.Runspace = $apiRunspace
$apiPs.Runspace.SessionStateProxy.SetVariable("AppIdCombo", $AppIdCombo)
$apiPs.Runspace.SessionStateProxy.SetVariable("Dispatcher", $Dispatcher)

[void]$apiPs.AddScript({
    try {
        $Dispatcher.Invoke([Action]{ $AppIdCombo.Text = "Loading supported games..." })
        $apiUrl = "https://steamunlockonennabe.duckdns.org/api/onennabe"
        $apiData = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        
        $supportedGames = $apiData | Where-Object { $_.online_supported -eq 'Yes' -or $_.bypass_supported -eq 'Yes' }
        
        $Dispatcher.Invoke([Action]{
            $AppIdCombo.Text = ""
            $AppIdCombo.Items.Clear()
            foreach ($game in $supportedGames) {
                [void]$AppIdCombo.Items.Add("$($game.appid) - $($game.name)")
            }
            if ($supportedGames.Count -gt 0) {
                $AppIdCombo.SelectedIndex = 0
            }
        })
    } catch {
        $Dispatcher.Invoke([Action]{
            $AppIdCombo.Text = ""
            $AppIdCombo.ToolTip = "Failed to load API data."
            [void]$AppIdCombo.Items.Add("2358720") # Fallback to default
        })
    }
})

$apiPs.BeginInvoke() | Out-Null

# Helper to write to UI from main thread
function Update-Log {
    param([string]$Message)
    $Dispatcher.Invoke([Action]{
        $LogTextBox.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`r`n")
        $LogTextBox.ScrollToEnd()
    })
}

$ClearLogButton.Add_Click({
    $LogTextBox.Clear()
})

# --- Step 2: Handle Start Button Click (Async Execution) ---
$StartButton.Add_Click({
    $appIdRaw = $AppIdCombo.Text.Trim()
    
    if ([string]::IsNullOrWhiteSpace($appIdRaw) -or $appIdRaw -eq "Loading supported games...") {
        [System.Windows.MessageBox]::Show("Please enter a valid AppID.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    # Extract AppID from format "AppID - Name" if a dropdown item was selected
    $appId = ($appIdRaw -split ' - ')[0].Trim()

    $StartButton.IsEnabled = $false
    Update-Log "Starting patch process for AppID: $appId"

    # Set up runspace for background processing to keep UI responsive
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $runspace
    
    # Pass variables into the runspace so it can communicate with the main UI thread
    $ps.Runspace.SessionStateProxy.SetVariable("AppID", $appId)
    $ps.Runspace.SessionStateProxy.SetVariable("Dispatcher", $Dispatcher)
    $ps.Runspace.SessionStateProxy.SetVariable("LogTextBox", $LogTextBox)
    $ps.Runspace.SessionStateProxy.SetVariable("StartButton", $StartButton)

    # -------------------------------------------------------------
    # BACKGROUND LOGIC STARTS HERE
    # -------------------------------------------------------------
    [void]$ps.AddScript({
        
        # Helper inside Runspace to dispatch to UI
        function Write-AppLog {
            param([string]$Message)
            $Dispatcher.Invoke([Action]{
                $LogTextBox.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $Message`r`n")
                $LogTextBox.ScrollToEnd()
            })
        }

        try {
            # --- Step 1: Detect Steam Path ---
            Write-AppLog "Detecting Steam Path..."
            $steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
            if (-not $steamPath) {
                $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
            }
            if (-not $steamPath) {
                Write-AppLog "ERROR: Steam installation not found!"
                return
            }

            # --- Step 2: Find appmanifest ---
            Write-AppLog "Checking main Steam steamapps folder first..."
            $appManifest = $null
            $mainSteamApps = Join-Path $steamPath "steamapps"
            if (Test-Path $mainSteamApps) {
                $acf = Get-ChildItem -Path $mainSteamApps -Filter "appmanifest_$AppID.acf" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($acf) { $appManifest = $acf }
            }

            if (-not $appManifest) {
                Write-AppLog "Not in main Steam folder. Scanning mounted drives..."
                $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
                foreach ($drive in $drives) {
                    if (-not (Test-Path $drive)) { continue }
                    $libs = @( (Join-Path $drive "SteamLibrary"), (Join-Path $drive "Steam") )
                    foreach ($lib in $libs) {
                        if (-not (Test-Path $lib)) { continue }
                        $steamApps = Join-Path $lib "steamapps"
                        if (-not (Test-Path $steamApps)) { continue }
                        $acf = Get-ChildItem -Path $steamApps -Filter "appmanifest_$AppID.acf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($acf) {
                            $appManifest = $acf
                            break
                        }
                    }
                    if ($appManifest) { break }
                }
            }

            if (-not $appManifest) {
                Write-AppLog "ERROR: AppID $AppID not found in any Steam library folder!"
                return
            }

            Write-AppLog "Found manifest: $($appManifest.FullName)"

            # --- Step 3: Parse installdir ---
            $acfContent = Get-Content $appManifest.FullName
            $installDirLine = $acfContent | Where-Object { $_ -match '"installdir"' }
            $installDir = ($installDirLine -split '"')[3]

            # --- Step 4: Build REAL game path ---
            $libraryRoot = Split-Path (Split-Path $appManifest.FullName -Parent) -Parent
            $gamePath = Join-Path (Join-Path $libraryRoot "steamapps\common") $installDir
            Write-AppLog "Detected game folder: $gamePath"

            # --- Step 5: Get file list from GitHub ---
            $branch = $AppID
            $repo1Owner = "3circledesign"
            $repo1Name = "intestingpowershell"
            $repo2Owner = "CrabBerjoget"
            $repo2Name = "intestingpowershell"

            Write-AppLog "Fetching source from GitHub branch: $branch..."
            
            function Get-GitHubFilesInner($owner, $name, $branch) {
                $url = "https://api.github.com/repos/$owner/$name/contents/?ref=$branch"
                try {
                    return Invoke-RestMethod -Uri $url -UseBasicParsing -Headers @{ "User-Agent" = "PowerShell" }
                } catch {
                    return $null
                }
            }

            $filesList = Get-GitHubFilesInner $repo1Owner $repo1Name $branch
            if (-not $filesList) {
                Write-AppLog "Refetching source from backup repo..."
                $filesList = Get-GitHubFilesInner $repo2Owner $repo2Name $branch
                if (-not $filesList) {
                    Write-AppLog "ERROR: No Patch for branch $branch yet!"
                    return
                }
            }

            Write-AppLog "Patch Found on GitHub. Starting Downloads..."

            # --- Step 6: Multi-thread Download ---
            $runspacePool = [runspacefactory]::CreateRunspacePool(1, 10)
            $runspacePool.Open()
            $runspaces = @()

            foreach ($file in $filesList) {
                if ($file.type -eq "file") {
                    $fileUrl = $file.download_url
                    $fileName = $file.name
                    $destination = Join-Path $gamePath $fileName

                    Write-AppLog "Queueing download: $fileName"

                    $dlPs = [powershell]::Create()
                    $dlPs.RunspacePool = $runspacePool
                    [void]$dlPs.AddScript({
                        param($url, $out)
                        try {
                            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
                        } catch {
                            throw $_
                        }
                    }).AddArgument($fileUrl).AddArgument($destination)

                    $handle = $dlPs.BeginInvoke()
                    $runspaces += @{ PowerShell = $dlPs; Handle = $handle; FileName = $fileName }
                }
            }

            # Wait and handle errors for downloads
            $dlError = $false
            foreach ($r in $runspaces) {
                try {
                    $r.PowerShell.EndInvoke($r.Handle)
                    if ($r.PowerShell.HadErrors) {
                        Write-AppLog "FAILED to download: $($r.FileName)"
                        $dlError = $true
                    }
                } catch {
                     Write-AppLog "FAILED to download: $($r.FileName) ($($_))"
                     $dlError = $true
                } finally {
                    $r.PowerShell.Dispose()
                }
            }
            $runspacePool.Close()
            $runspacePool.Dispose()
            
            if ($dlError) {
                Write-AppLog "WARNING: Some downloads failed."
            } else {
                Write-AppLog "All downloads completed successfully!"
            }

            # --- Step 7: Ensure UnRAR.exe is downloaded ---
            $unrarPath = Join-Path $gamePath "UnRAR.exe"
            if (-not (Test-Path $unrarPath)) {
                Write-AppLog "Downloading UnRAR.exe..."
                try {
                    Invoke-WebRequest -Uri "https://github.com/CrabBerjoget/intestingpowershell/raw/main/UnRAR.exe" -OutFile $unrarPath -UseBasicParsing
                } catch {
                    Write-AppLog "Failed to download UnRAR.exe. RAR extraction will be skipped."
                    $unrarPath = $null
                }
            }

            # --- Step 8: Safe Runspace RAR Extraction ---
            $rarFiles = Get-ChildItem -Path $gamePath -Recurse -Filter *.rar
            
            if ($unrarPath -and (Test-Path $unrarPath) -and $rarFiles.Count -gt 0) {
                Write-AppLog "Starting Extraction..."
                
                $rarGroups = @{}
                foreach ($rar in $rarFiles) {
                    $baseName = ($rar.Name -replace '\.part\d+\.rar$', '') -replace '\.rar$', ''
                    if (-not $rarGroups.ContainsKey($baseName)) { $rarGroups[$baseName] = @() }
                    $rarGroups[$baseName] += $rar
                }

                $extPool = [runspacefactory]::CreateRunspacePool(1, 4)
                $extPool.Open()
                $extRunspaces = @()

                foreach ($group in $rarGroups.GetEnumerator()) {
                    $firstRar = $group.Value | Sort-Object FullName | Select-Object -First 1
                    Write-AppLog "Extracting: $($firstRar.Name)"

                    $extPs = [powershell]::Create()
                    $extPs.RunspacePool = $extPool
                    [void]$extPs.AddScript({
                        param($firstRarPath, $rarSet, $unrarExe)
                        $dest = Split-Path $firstRarPath -Parent
                        
                        $p = Start-Process -FilePath $unrarExe -ArgumentList "x `"$firstRarPath`" `"$dest`" -y -inul" -WindowStyle Hidden -Wait -PassThru
                        
                        # Full cleanup: remove all parts in the set
                        if ($p.ExitCode -eq 0) {
                            foreach ($rarFile in $rarSet) {
                                if (Test-Path $rarFile.FullName) { Remove-Item $rarFile.FullName -Force }
                            }
                        } else {
                            throw "UnRAR failed with exit code $($p.ExitCode)"
                        }
                    }).AddArgument($firstRar.FullName).AddArgument($group.Value).AddArgument($unrarPath)

                    $extHandle = $extPs.BeginInvoke()
                    $extRunspaces += @{ PowerShell = $extPs; Handle = $extHandle; Name = $firstRar.Name }
                }

                foreach ($r in $extRunspaces) {
                    try {
                        $r.PowerShell.EndInvoke($r.Handle)
                        if ($r.PowerShell.HadErrors) {
                            Write-AppLog "Extraction failed for $($r.Name)"
                        }
                    } catch {
                        Write-AppLog "Extraction error for $($r.Name): $_"
                    } finally {
                        $r.PowerShell.Dispose()
                    }
                }
                $extPool.Close()
                $extPool.Dispose()
                
                Write-AppLog "File extraction and cache cleanup complete!"
            } elseif ($rarFiles.Count -eq 0) {
                Write-AppLog "No .rar files found to extract."
            }

            Write-AppLog "=============================="
            Write-AppLog "Patch Process Complete!"
            Write-AppLog "Happy Gaming!"
            Write-AppLog "=============================="

        } catch {
            Write-AppLog "FATAL ERROR: $_"
        } finally {
            # Re-enable the button when done
            $Dispatcher.Invoke([Action]{
                $StartButton.IsEnabled = $true
            })
        }
    })

    # Start the background script asynchronously
    $ps.BeginInvoke()

})

# Show the GUI
Update-Log "WannabePatcher GUI Initialized. Ready."
$Window.ShowDialog() | Out-Null
