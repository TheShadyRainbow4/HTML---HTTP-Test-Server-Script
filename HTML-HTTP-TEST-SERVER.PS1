# EliteSoftware HTML - HTTP Test Server v1.4.2.0 - Created by: Zachary Whiteman & Google Gemini Ai. 2025-10-11 - 03:30 EDT

<#
    This script implements a multi-server HTTP test platform GUI using PowerShell WinForms and threading.

    FIXES IN V1.4.2.0:
    - **Fixed Instant Crash:** Corrected a critical syntax error in the "Duplicate Configuration" logic that caused the application to crash immediately on launch.
#>

# ==============================================================================
# 1. Dependency and Configuration Setup
# ==============================================================================

# Script Versioning
[string]$ScriptVersion = "v1.4.2.0"

# Load required .NET assemblies
# The 'Add-Type' for Drawing2D often generates a benign file-not-found error in some editors,
# but it loads correctly from the GAC. We suppress the warning.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net
try {
    Add-Type -AssemblyName "System.Drawing.Drawing2D, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a" -ErrorAction SilentlyContinue
} catch {
    # This space intentionally left blank.
}

# Enable system visual styles (essential for theming)
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Configuration Path Update ---
$appId = "HTML_HTTP_TEST_SERVER"
# Requested specific path: C:\Users\Zachary Whiteman\AppData\Roaming\EliteSoftware\HTML_HTTP_TEST_SERVER
$baseConfigPath = "C:\Users\Zachary Whiteman\AppData\Roaming\EliteSoftware"
$configPath = Join-Path -Path $baseConfigPath -ChildPath $appId
$configFile = Join-Path -Path $configPath -ChildPath "server_configs.json"
$iconFile = Join-Path -Path $configPath -ChildPath "custom-icon.ico"

if (-not (Test-Path $configPath)) {
    New-Item -Path $configPath -ItemType Directory -Force | Out-Null
}

# --- Icon Loading ---
function Get-AppIcon {
    if (Test-Path $iconFile) {
        return [System.Drawing.Icon]::new($iconFile)
    }
    # Default icon fallback
    return [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\system32\shell32.dll")
}

# Variable Definitions
[int]$FormWidth = 900 # Increased width for sidebar
[int]$FormHeight = 610
[int]$xStart = 30 # X coordinate for starting controls
[int]$SidebarWidth = 250
[int]$ContentXStart = $SidebarWidth + 30 # Start of main controls
[int]$ContentWidth = $FormWidth - $ContentXStart - $xStart # Width of the right panel
[int]$padding = 20 # Vertical padding offset
[int]$ButtonWidth = 140 # Adjusted button size
[int]$ButtonHeight = 40
[int]$BorderThickness = 2

# --- Global State Variables ---
$Script:ServerConfigs = @() # Array of saved configuration objects
$Script:CurrentConfigIndex = 0 # Index of the currently selected configuration
$Script:ActiveServers = @{} # Hashtable to track running HttpListener objects {ConfigName: {Listener: <obj>, Thread: <obj>}}
$Script:LogQueue = [System.Collections.Queue]::new() # Thread-safe queue for logging
$Script:LogTimer = $null # Timer for polling the log queue
$Script:IsExiting = $false # Flag for graceful exit
$Script:Settings = $null # Global settings object

# ==============================================================================
# 2. Configuration Management Functions
# ==============================================================================

function Load-Settings {
    $settingsFile = Join-Path -Path $configPath -ChildPath "settings.json"
    $defaultSettings = @{
        DefaultRoot = "C:\inetpub\wwwroot"
        DefaultFile = "index.html"
        DefaultPort = 8080
        DefaultIP = "127.0.0.1"
        MaxLogLines = 200
        LogToFile = $false
        LogFilePath = (Join-Path -Path $configPath -ChildPath "server.log")
        ShowGoodbyeWindow = $true
    }

    if (Test-Path $settingsFile) {
        try {
            $json = Get-Content $settingsFile -Raw
            $Script:Settings = $json | ConvertFrom-Json
            # Ensure all default keys exist
            foreach ($key in $defaultSettings.Keys) {
                if (-not $Script:Settings.PSObject.Properties.Match($key)) {
                    $Script:Settings | Add-Member -MemberType NoteProperty -Name $key -Value $defaultSettings[$key]
                }
            }
        } catch {
            Write-Warning "Failed to load settings.json, using defaults. Error: $($_.Exception.Message)"
            $Script:Settings = [PSCustomObject]$defaultSettings
        }
    } else {
        $Script:Settings = [PSCustomObject]$defaultSettings
    }
}

function Save-Settings {
    $settingsFile = Join-Path -Path $configPath -ChildPath "settings.json"
    try {
        $Script:Settings | ConvertTo-Json -Depth 3 | Out-File -FilePath $settingsFile -Encoding UTF8
    } catch {
        Write-Error "Failed to save settings to '$settingsFile'. Error: $($_.Exception.Message)"
    }
}

function Save-ServerConfig {
    try {
        # Limit to 10 configs as requested
        $configsToSave = $Script:ServerConfigs | Select-Object -First 10
        $json = $configsToSave | ConvertTo-Json -Depth 5
        $json | Out-File $configFile -Encoding UTF8
    } catch {
        Write-Error "Failed to save configuration: $($_.Exception.Message)"
    }
}

function Load-ServerConfigs {
    if (Test-Path $configFile) {
        try {
            $json = Get-Content $configFile -Raw
            $loadedConfigs = $json | ConvertFrom-Json
            if ($loadedConfigs -is [System.Array]) {
                $Script:ServerConfigs = $loadedConfigs
            } elseif ($loadedConfigs -is [System.Management.Automation.PSCustomObject]) {
                 # Handle case where only one config was saved (ConvertFrom-Json returns a single object)
                $Script:ServerConfigs = @($loadedConfigs)
            } else {
                $Script:ServerConfigs = @()
            }
        } catch {
            Write-Log "WARNING: Failed to load configurations. Starting fresh. $($_.Exception.Message)"
            $Script:ServerConfigs = @()
        }
    }

    # Initialize with a default config if none loaded
    if (-not $Script:ServerConfigs) {
        $Script:ServerConfigs = @(
            [PSCustomObject]@{
                Name = "Default Server 1"
                Root = "C:\inetpub\wwwroot"
                DefaultFile = "index.html"
                Port = 8080
                IP = "127.0.0.1"
                Status = "Stopped"
                UseRootFolderMode = $false
                SingleFilePath = "C:\path\to\your\file.html"
                AutoStart = $false
            }
        )
    }

    # Ensure all configs have the required properties
    $Script:ServerConfigs = $Script:ServerConfigs | ForEach-Object {
        if (-not $_.PSObject.Properties.Match('Status')) {
            $_ | Add-Member -MemberType NoteProperty -Name Status -Value "Stopped" -Force
        }
        if (-not $_.PSObject.Properties.Match('UseRootFolderMode')) {
            $_ | Add-Member -MemberType NoteProperty -Name UseRootFolderMode -Value $false -Force
        }
        if (-not $_.PSObject.Properties.Match('SingleFilePath')) {
            $_ | Add-Member -MemberType NoteProperty -Name SingleFilePath -Value "" -Force
        }
        if (-not $_.PSObject.Properties.Match('AutoStart')) {
            $_ | Add-Member -MemberType NoteProperty -Name AutoStart -Value $false -Force
        }
        $_
    }
}

function Add-NewConfig {
    # Find the highest port number currently in use and add 1
    $nextPort = if ($Script:ServerConfigs.Count -gt 0) {
        ($Script:ServerConfigs.Port | ForEach-Object { [int]$_ } | Measure-Object -Maximum).Maximum + 1
    } else {
        $Script:Settings.DefaultPort # Start with default if no servers exist
    }

    $newConfig = [PSCustomObject]@{
        Name = "New Server $($Script:ServerConfigs.Count + 1)"
        Root = $Script:Settings.DefaultRoot
        DefaultFile = $Script:Settings.DefaultFile
        Port = $nextPort
        IP = $Script:Settings.DefaultIP
        Status = "Stopped"
        UseRootFolderMode = $false
        SingleFilePath = ""
        AutoStart = $false
    }
    $Script:ServerConfigs += $newConfig
    Save-ServerConfig
}

function Update-GUIFromConfig {
    if ($Script:ServerConfigs.Count -gt $Script:CurrentConfigIndex -and $Form.IsHandleCreated) {
        $config = $Script:ServerConfigs[$Script:CurrentConfigIndex]
        $Form.Invoke([System.Action] {
            $configParam = $Script:ServerConfigs[$Script:CurrentConfigIndex]
            # Update common controls
            $PortTextBox.Text = $configParam.Port
            $IPComboBox.Text = $configParam.IP

            # Update mode-specific controls
            $RootModeCheckBox.Checked = $configParam.UseRootFolderMode
            $RootTextBox.Text = $configParam.Root
            $DefaultFileTextBox.Text = $configParam.DefaultFile
            $SingleFileTextBox.Text = $configParam.SingleFilePath
            $AutoStartCheckBox.Checked = $configParam.AutoStart

            # Toggle visibility based on mode
            $isRootMode = $configParam.UseRootFolderMode
            $RootLabel.Visible = $isRootMode
            $RootTextBox.Visible = $isRootMode
            $BrowseButton.Visible = $isRootMode
            $DefaultFileLabel.Visible = $isRootMode
            $DefaultFileTextBox.Visible = $isRootMode
            $SingleFileLabel.Visible = -not $isRootMode
            $SingleFileTextBox.Visible = -not $isRootMode
            $SingleFileBrowseButton.Visible = -not $isRootMode

            # Update form text and header
            $Form.Text = "EliteSoftware HTTP Test Server - $($configParam.Name)"
            $HeaderLabel.Text = "HTTP Server: $($configParam.Name)"

            $SidebarList.SelectedIndex = $Script:CurrentConfigIndex
            Update-ServerButtons $configParam.Status # Update buttons based on the config's status
        })
    }
}

function Update-ConfigFromGUI {
    if ($Script:ServerConfigs.Count -gt $Script:CurrentConfigIndex) {
        $config = $Script:ServerConfigs[$Script:CurrentConfigIndex]
        # Ensure the object is a modifiable PSCustomObject
        if ($config -isnot [System.Management.Automation.PSCustomObject]) {
            $config = $config | Select-Object *
            $Script:ServerConfigs[$Script:CurrentConfigIndex] = $config
        }
        $config.Root = $RootTextBox.Text
        $config.DefaultFile = $DefaultFileTextBox.Text
        $config.Port = [int]$PortTextBox.Text
        $config.IP = $IPComboBox.Text
        $config.UseRootFolderMode = $RootModeCheckBox.Checked
        $config.SingleFilePath = $SingleFileTextBox.Text
        $config.AutoStart = $AutoStartCheckBox.Checked
        Save-ServerConfig
    }
}

# ==============================================================================
# 3. HTTP Server and Request Handling
# ==============================================================================

function Get-LocalIPv4Addresses {
    Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias * | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.InterfaceType -ne 'Loopback' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -ExpandProperty IPAddress
}



# ==============================================================================
# 3. HTTP Server and Request Handling
# ==============================================================================

function Start-Server {
    param($config)

    # 1. Update Config Status
    $config.Status = "Starting"
    Update-GUIFromConfig # Update buttons/status indicator

    # 2. Check and Adjust Port (Conflict Resolution)
    [string]$prefix = "http://$($config.IP):$($config.Port)/"
    $port = [int]$config.Port

    while ([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port -contains $port) {
        $port++
        $prefix = "http://$($config.IP):$port/"
        Invoke-GUIUpdate { Write-Log "Port $($port-1) is in use. Retrying on port $port..." }
        $config.Port = $port
        $PortTextBox.Text = $port
        Update-ConfigFromGUI
    }

    # 3. Create HttpListener and Thread
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)

    $thread = [System.Threading.Thread]::new({
        # Thread ScriptBlock
        param($listener, $config, $LogQueue, $Script:IsExiting)
        $listener.Start()
        $listenerState = $listener.IsListening

        $LogQueue.Enqueue("Server started successfully on $prefix. Root: $($config.Root)")

        while ($listener.IsListening -and -not $Script:IsExiting) {
            try {
                # Wait for a request asynchronously
                $context = $listener.GetContext()

                # Process the request
                $request = $context.Request
                $response = $context.Response
                $filePath = ""
                $fullPath = ""
                [int]$status = 404 # Default to Not Found
                [long]$fileSize = 0

                try {
                    if ($config.UseRootFolderMode) {
                        # ROOT FOLDER MODE LOGIC
                        $filePath = $request.Url.LocalPath.TrimStart('/')
                        if ([string]::IsNullOrEmpty($filePath) -or $filePath -eq '/') {
                            $filePath = $config.DefaultFile
                        }
                        
                        # Prevent directory traversal
                        if ($filePath.Contains('..')) {
                            throw [System.Security.SecurityException]::new("Directory traversal attempt detected.")
                        }

                        $fullPath = Join-Path -Path $config.Root -ChildPath $filePath
                    } else {
                        # SINGLE FILE MODE LOGIC
                        $filePath = [System.IO.Path]::GetFileName($config.SingleFilePath)
                        $fullPath = $config.SingleFilePath
                    }


                    if (Test-Path $fullPath -PathType Leaf) {
                        # Serve file
                        $fileStream = [System.IO.File]::OpenRead($fullPath)
                        $fileInfo = Get-Item $fullPath
                        $fileSize = $fileInfo.Length

                        $response.ContentType = [System.Web.MimeMapping]::GetMimeMapping($fullPath)
                        $response.ContentLength64 = $fileSize
                        $response.StatusCode = 200
                        $status = 200

                        $fileStream.CopyTo($response.OutputStream)
                        $fileStream.Dispose()

                    } else {
                        # 404 Not Found
                        $status = 404
                        $response.StatusCode = 404
                        $response.StatusDescription = "Not Found"
                        $output = [System.Text.Encoding]::UTF8.GetBytes("<html><head><title>404 Not Found</title></head><body><h1>EliteServer 404</h1><p>The requested file ($filePath) was not found in the root directory.</p></body></html>")
                        $response.ContentLength64 = $output.Length
                        $response.OutputStream.Write($output, 0, $output.Length)
                    }

                } catch {
                    # 500 Server Error
                    $status = 500
                    $response.StatusCode = 500
                    $response.StatusDescription = "Internal Server Error"
                    $LogQueue.Enqueue("ERROR: Request for $($filePath) failed: $($_.Exception.Message)")
                } finally {
                    $response.OutputStream.Close()
                }

                # Log the request using the detailed format (B)
                $logMessage = "[$status] $($request.RemoteEndPoint.Address) - $($request.HttpMethod) /$filePath (File Size: $([Math]::Round($fileSize / 1KB, 2)) KB)"
                $LogQueue.Enqueue($logMessage)


            } catch [System.Net.HttpListenerException] {
                # Listener stopped gracefully
                break
            } catch {
                # General Thread Error
                $LogQueue.Enqueue("CRITICAL ERROR in listener loop: $($_.Exception.Message)")
                # Exit the loop on critical error
                break
            }
        } # End while loop

        # Final cleanup outside the loop
        if ($listener.IsListening) {
             $listener.Close()
        }
        $LogQueue.Enqueue("Listener for $($config.Name) terminated.")
    }).Dispose()

    # 4. Start the Thread
    $thread.IsBackground = $true # Ensure thread stops when main process exits
    $thread.Start($listener, $config, $Script:LogQueue, $Script:IsExiting)

    # 5. Update Global State
    $Script:ActiveServers[$config.Name] = @{
        Listener = $listener
        Thread = $thread
        Prefix = $prefix
    }
    $config.Status = "Running"
    Update-GUIFromConfig # Update buttons/status indicator
    Save-ServerConfig
}

function Stop-Server {
    param($config)
    
    if ($Script:ActiveServers.ContainsKey($config.Name)) {
        $serverInfo = $Script:ActiveServers[$config.Name]

        # Close the listener which will cause the thread's GetContext() to fail gracefully
        $serverInfo.Listener.Stop()
        $serverInfo.Listener.Close()

        # Remove from active list
        $Script:ActiveServers.Remove($config.Name)

        $config.Status = "Stopped"
        Save-ServerConfig
        Update-GUIFromConfig

        Invoke-GUIUpdate { Write-Log "Server '$($config.Name)' stopped gracefully." }
    }
}

# ==============================================================================
# 4. UI/Event Helper Functions
# ==============================================================================

function Draw-GradientHeader {
    param(
        [Parameter(Mandatory=$true)][System.Object]$sender,
        [Parameter(Mandatory=$true)][System.Windows.Forms.PaintEventArgs]$e
    )
    # Gradient Fix: Using static new() method and explicit casting to ensure correct overload matching
    $g = $e.Graphics
    $rect = $sender.ClientRectangle
    $color1 = [System.Drawing.Color]::FromArgb(255, 0, 128, 128) # Teal
    $color2 = [System.Drawing.Color]::FromArgb(255, 128, 0, 128) # Violet

    try {
        $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $rect,
            $color1,
            $color2,
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
        )
    } catch {
        $brush = [System.Drawing.SolidBrush]::new($color1)
    }
    if ($brush) {
        $g.FillRectangle($brush, $rect)
        $brush.Dispose()
    }
}

function Update-ServerButtons {
    param($status)
    $StartButton.Enabled = ($status -ne "Running")
    $StopButton.Enabled = ($status -eq "Running")
    $OpenBrowserButton.Enabled = ($status -eq "Running")

    if ($status -eq "Running") {
        $StatusIndicator.Text = "Status: Running on $($PortTextBox.Text)"
        $StatusIndicator.ForeColor = [System.Drawing.Color]::Green
    } else {
        $StatusIndicator.Text = "Status: Stopped"
        $StatusIndicator.ForeColor = [System.Drawing.Color]::Red
    }
}

function Write-Log ($message) {
    if ($LogTextBox) {
        $LogTextBox.AppendText("$(Get-Date -Format 'HH:mm:ss') - $message`r`n")
        # Clean up old log lines if it gets too long
        if ($LogTextBox.Lines.Count -gt $Script:Settings.MaxLogLines) {
            $LogTextBox.Text = $LogTextBox.Text.Substring($LogTextBox.Lines[0].Length + 2)
        }
    } else {
        # Fallback to console if LogTextBox is not yet initialized
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - $message"
    }

    if ($Script:Settings.LogToFile) {
        try {
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message" | Out-File -FilePath $Script:Settings.LogFilePath -Append -Encoding UTF8
        } catch {
            # Disable to prevent spamming errors
            $Script:Settings.LogToFile = $false
            Write-Log "ERROR: Could not write to log file '$($Script:Settings.LogFilePath)'. Disabling file logging. Error: $($_.Exception.Message)"
        }
    }
}

# Timer to poll the log queue and update the GUI safely
function Start-LogTimer {
    $Script:LogTimer = [System.Windows.Forms.Timer]::new()
    $Script:LogTimer.Interval = 100 # Check every 100ms
    $Script:LogTimer.Add_Tick({
        # Process log messages from the queue
        while ($Script:LogQueue.Count -gt 0) {
            $message = $Script:LogQueue.Dequeue()
            Write-Log $message
        }
    })
    $Script:LogTimer.Start()
}

function Show-GoodbyeWindow {
    param($Message)
    
    $GoodbyeForm = [System.Windows.Forms.Form]::new()
    $GoodbyeForm.Text = "Closing Application"
    $GoodbyeForm.Size = [System.Drawing.Size]::new(500, 200)
    $GoodbyeForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $GoodbyeForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    
    # Paint the gradient directly onto the form's background
    $GoodbyeForm.Add_Paint({
        param($sender, $e)
        Draw-GradientHeader $sender $e
    })

    # Message Label (Matches Header Font/Color)
    $GoodbyeLabel = [System.Windows.Forms.Label]::new()
    $GoodbyeLabel.Text = $Message
    $GoodbyeLabel.Font = [System.Drawing.Font]::new("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
    $GoodbyeLabel.ForeColor = [System.Drawing.Color]::White
    $GoodbyeLabel.BackColor = [System.Drawing.Color]::Transparent
    $GoodbyeLabel.AutoSize = $true
    
    # Center the label
    $GoodbyeForm.Controls.Add($GoodbyeLabel)

    # Show the modal form non-blockingly
    $GoodbyeForm.Show() | Out-Null
    
    # Update label location after it has been shown and sized
    $GoodbyeLabel.Location = [System.Drawing.Point]::new(($GoodbyeForm.Width - $GoodbyeLabel.Width) / 2, ($GoodbyeForm.Height - $GoodbyeLabel.Height) / 2)

    # Use a System.Threading.Timer for non-blocking delay
    $delayTimer = [System.Threading.Timer]::new({
        $GoodbyeForm.Close()
        $Form.Close()
    }, $null, 2500, [System.Threading.Timeout]::Infinite)
    
    $GoodbyeForm.Tag = $delayTimer # Hold reference to prevent garbage collection
}

function Show-SettingsWindow {
    $SettingsForm = [System.Windows.Forms.Form]::new()
    $SettingsForm.Text = "Application Settings"
    $SettingsForm.Size = [System.Drawing.Size]::new(550, 450)
    $SettingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $SettingsForm.MinimizeBox = $false
    $SettingsForm.MaximizeBox = $false
    $SettingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $SettingsForm.BackColor = [System.Drawing.Color]::FromArgb(255, 240, 240, 240)

    $yPos = 20
    $xPos = 20
    $labelWidth = 200
    $controlWidth = 280

    # --- Default Root ---
    $DefaultRootLabel = [System.Windows.Forms.Label]::new()
    $DefaultRootLabel.Text = "Default Root for New Servers:"
    $DefaultRootLabel.AutoSize = $true
    $DefaultRootLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $SettingsForm.Controls.Add($DefaultRootLabel)

    $DefaultRootTextBox = [System.Windows.Forms.TextBox]::new()
    $DefaultRootTextBox.Text = $Script:Settings.DefaultRoot
    $DefaultRootTextBox.Width = $controlWidth
    $DefaultRootTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $SettingsForm.Controls.Add($DefaultRootTextBox)
    $yPos += 35

    # --- Default File ---
    $DefaultFileLabel = [System.Windows.Forms.Label]::new()
    $DefaultFileLabel.Text = "Default File for New Servers:"
    $DefaultFileLabel.AutoSize = $true
    $DefaultFileLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $SettingsForm.Controls.Add($DefaultFileLabel)

    $DefaultFileTextBox = [System.Windows.Forms.TextBox]::new()
    $DefaultFileTextBox.Text = $Script:Settings.DefaultFile
    $DefaultFileTextBox.Width = $controlWidth
    $DefaultFileTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $SettingsForm.Controls.Add($DefaultFileTextBox)
    $yPos += 35

    # --- Default Port ---
    $DefaultPortLabel = [System.Windows.Forms.Label]::new()
    $DefaultPortLabel.Text = "Default Port for New Servers:"
    $DefaultPortLabel.AutoSize = $true
    $DefaultPortLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $SettingsForm.Controls.Add($DefaultPortLabel)

    $DefaultPortTextBox = [System.Windows.Forms.TextBox]::new()
    $DefaultPortTextBox.Text = $Script:Settings.DefaultPort
    $DefaultPortTextBox.Width = $controlWidth
    $DefaultPortTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $SettingsForm.Controls.Add($DefaultPortTextBox)
    $yPos += 35

    # --- Default IP Address ---
    $DefaultIPLabel = [System.Windows.Forms.Label]::new()
    $DefaultIPLabel.Text = "Default IP for New Servers:"
    $DefaultIPLabel.AutoSize = $true
    $DefaultIPLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $SettingsForm.Controls.Add($DefaultIPLabel)

    $DefaultIPComboBox = [System.Windows.Forms.ComboBox]::new()
    $DefaultIPComboBox.Items.Add("127.0.0.1")
    $DefaultIPComboBox.Items.AddRange((Get-LocalIPv4Addresses))
    $DefaultIPComboBox.Text = $Script:Settings.DefaultIP
    $DefaultIPComboBox.Width = $controlWidth
    $DefaultIPComboBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $SettingsForm.Controls.Add($DefaultIPComboBox)
    $yPos += 35

    # --- Max Log Lines ---
    $MaxLogLinesLabel = [System.Windows.Forms.Label]::new()
    $MaxLogLinesLabel.Text = "Max Log Lines in GUI:"
    $MaxLogLinesLabel.AutoSize = $true
    $MaxLogLinesLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $SettingsForm.Controls.Add($MaxLogLinesLabel)

    $MaxLogLinesTextBox = [System.Windows.Forms.TextBox]::new()
    $MaxLogLinesTextBox.Text = $Script:Settings.MaxLogLines
    $MaxLogLinesTextBox.Width = $controlWidth
    $MaxLogLinesTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $SettingsForm.Controls.Add($MaxLogLinesTextBox)
    $yPos += 35

    # --- Log to File Checkbox ---
    $LogToFileCheckBox = [System.Windows.Forms.CheckBox]::new()
    $LogToFileCheckBox.Text = "Enable Logging to File"
    $LogToFileCheckBox.Checked = $Script:Settings.LogToFile
    $LogToFileCheckBox.AutoSize = $true
    $LogToFileCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $SettingsForm.Controls.Add($LogToFileCheckBox)
    $yPos += 35

    # --- Log File Path ---
    $LogFilePathLabel = [System.Windows.Forms.Label]::new()
    $LogFilePathLabel.Text = "Log File Path:"
    $LogFilePathLabel.AutoSize = $true
    $LogFilePathLabel.Location = [System.Drawing.Point]::new($xPos, $yPos + 3)
    $SettingsForm.Controls.Add($LogFilePathLabel)

    $LogFilePathTextBox = [System.Windows.Forms.TextBox]::new()
    $LogFilePathTextBox.Text = $Script:Settings.LogFilePath
    $LogFilePathTextBox.Width = $controlWidth
    $LogFilePathTextBox.Location = [System.Drawing.Point]::new($xPos + $labelWidth, $yPos)
    $SettingsForm.Controls.Add($LogFilePathTextBox)
    $yPos += 35

    # --- Show Goodbye Window Checkbox ---
    $ShowGoodbyeCheckBox = [System.Windows.Forms.CheckBox]::new()
    $ShowGoodbyeCheckBox.Text = "Show Goodbye Window on Exit"
    $ShowGoodbyeCheckBox.Checked = $Script:Settings.ShowGoodbyeWindow
    $ShowGoodbyeCheckBox.AutoSize = $true
    $ShowGoodbyeCheckBox.Location = [System.Drawing.Point]::new($xPos, $yPos)
    $SettingsForm.Controls.Add($ShowGoodbyeCheckBox)
    $yPos += 50

    # --- Save and Cancel Buttons ---
    $SaveButton = [System.Windows.Forms.Button]::new()
    $SaveButton.Text = "Save"
    $SaveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $SaveButton.Location = [System.Drawing.Point]::new($SettingsForm.Width - 220, $SettingsForm.Height - 80)
    $SaveButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $SettingsForm.Controls.Add($SaveButton)

    $CancelButton = [System.Windows.Forms.Button]::new()
    $CancelButton.Text = "Cancel"
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $CancelButton.Location = [System.Drawing.Point]::new($SettingsForm.Width - 130, $SettingsForm.Height - 80)
    $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $SettingsForm.Controls.Add($CancelButton)

    $SettingsForm.AcceptButton = $SaveButton
    $SettingsForm.CancelButton = $CancelButton

    if ($SettingsForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # Save the settings
        $Script:Settings.DefaultRoot = $DefaultRootTextBox.Text
        $Script:Settings.DefaultFile = $DefaultFileTextBox.Text
        $Script:Settings.DefaultPort = [int]$DefaultPortTextBox.Text
        $Script:Settings.DefaultIP = $DefaultIPComboBox.Text
        $Script:Settings.MaxLogLines = [int]$MaxLogLinesTextBox.Text
        $Script:Settings.LogToFile = $LogToFileCheckBox.Checked
        $Script:Settings.LogFilePath = $LogFilePathTextBox.Text
        $Script:Settings.ShowGoodbyeWindow = $ShowGoodbyeCheckBox.Checked
        Save-Settings
        Write-Log "Application settings saved."
    }

    $SettingsForm.Dispose()
}

function Show-HelpGuideWindow {
    $HelpForm = [System.Windows.Forms.Form]::new()
    $HelpForm.Text = "Help Guide"
    $HelpForm.Size = [System.Drawing.Size]::new(650, 550)
    $HelpForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $HelpForm.MinimizeBox = $false
    $HelpForm.MaximizeBox = $false
    $HelpForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $HelpForm.BackColor = [System.Drawing.Color]::White

    $HelpTextBox = [System.Windows.Forms.RichTextBox]::new()
    $HelpTextBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $HelpTextBox.ReadOnly = $true
    $HelpTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $HelpTextBox.Margin = [System.Windows.Forms.Padding]::new(15) # Add padding around the text
    $HelpTextBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical

    # --- Define Fonts ---
    $titleFont = [System.Drawing.Font]::new("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $headingFont = [System.Drawing.Font]::new("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $bodyFont = [System.Drawing.Font]::new("Segoe UI", 10)
    $headingColor = [System.Drawing.Color]::FromArgb(255, 0, 128, 128) # Teal

    # --- Helper function to append formatted text ---
    $AppendText = {
        param($Text, $Font, $Color = [System.Drawing.Color]::Black, $AddNewLine = $true)
        $HelpTextBox.SelectionStart = $HelpTextBox.TextLength
        $HelpTextBox.SelectionLength = 0
        $HelpTextBox.SelectionFont = $Font
        $HelpTextBox.SelectionColor = $Color
        $HelpTextBox.AppendText($Text + $(if ($AddNewLine) { "`r`n" } else { "" }))
    }

    # --- Build the Help Document ---
    $HelpTextBox.Clear()

    # Title
    & $AppendText -Text "EliteSoftware HTTP Test Server - Help Guide" -Font $titleFont -Color [System.Drawing.Color]::Black
    & $AppendText -Text "" -Font $bodyFont

    # Introduction
    & $AppendText -Text "Welcome! This guide explains how to use the application's features." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 1: Server Modes
    & $AppendText -Text "1. Server Modes" -Font $headingFont -Color $headingColor
    & $AppendText -Text "This application provides two primary modes for serving files:" -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont
    & $AppendText -Text "a) Single File Mode (Default)" -Font $bodyFont
    & $AppendText -Text "   - Use this mode to quickly serve a single HTML file." -Font $bodyFont
    & $AppendText -Text "   - The server will always respond with the content of the selected file, regardless of the URL path." -Font $bodyFont
    & $AppendText -Text "   - How to use:" -Font $bodyFont
    & $AppendText -Text "     1. Ensure 'Use Root Folder Mode' is UNCHECKED." -Font $bodyFont
    & $AppendText -Text "     2. Click 'Browse...' to select the HTML file you want to serve." -Font $bodyFont
    & $AppendText -Text "     3. Set your Port and IP, then click 'Start Server'." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont
    & $AppendText -Text "b) Root Folder Mode" -Font $bodyFont
    & $AppendText -Text "   - Use this mode to simulate a traditional web server by serving files from a directory." -Font $bodyFont
    & $AppendText -Text "   - The server will map URL paths to the file and folder structure within your selected root folder." -Font $bodyFont
    & $AppendText -Text "   - How to use:" -Font $bodyFont
    & $AppendText -Text "     1. CHECK the 'Use Root Folder Mode' box." -Font $bodyFont
    & $AppendText -Text "     2. Click 'Browse...' to select the main folder (root) for your website." -Font $bodyFont
    & $AppendText -Text "     3. Specify the 'Default File Name' (e.g., index.html) to be served for root requests ('/')." -Font $bodyFont
    & $AppendText -Text "     4. Set your Port and IP, then click 'Start Server'." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 2: Server Configurations
    & $AppendText -Text "2. Server Configurations" -Font $headingFont -Color $headingColor
    & $AppendText -Text "The panel on the left allows you to save and manage multiple server configurations." -Font $bodyFont
    & $AppendText -Text "   - Add a Server: Go to File > New Server Configuration." -Font $bodyFont
    & $AppendText -Text "   - Switch Servers: Simply click on a server name in the list to load its configuration." -Font $bodyFont
    & $AppendText -Text "   - Rename/Duplicate: Right-click a server in the list to access options." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 3: Main Controls
    & $AppendText -Text "3. Main Controls" -Font $headingFont -Color $headingColor
    & $AppendText -Text "   - Auto-Start Server: If checked, this server will start automatically when the application launches." -Font $bodyFont
    & $AppendText -Text "   - Use Root Folder Mode: Toggles between Single File and Root Folder modes." -Font $bodyFont
    & $AppendText -Text "   - Port: The network port the server will listen on. It auto-increments if the port is busy." -Font $bodyFont
    & $AppendText -Text "   - IP Address to Bind: The network interface to use. '127.0.0.1' is for local access only." -Font $bodyFont
    & $AppendText -Text "   - Start/Stop Server: Controls the currently selected server." -Font $bodyFont
    & $AppendText -Text "   - Open in Browser: Opens the server's URL in your default web browser." -Font $bodyFont
    & $AppendText -Text "   - Log Window: Displays live server activity, requests, and errors." -Font $bodyFont
    & $AppendText -Text "" -Font $bodyFont

    # Section 4: Settings
    & $AppendText -Text "4. Settings" -Font $headingFont -Color $headingColor
    & $AppendText -Text "Access via File > Settings..." -Font $bodyFont
    & $AppendText -Text "Here you can configure default values for new servers and control application behavior." -Font $bodyFont

    $HelpForm.Controls.Add($HelpTextBox)

    $HelpForm.ShowDialog() | Out-Null
    $HelpForm.Dispose()
}

# ==============================================================================
# 5. Form and Control Setup
# ==============================================================================

# Load configs and initialize icon before creating form
Load-Settings
Load-ServerConfigs
$AppIcon = Get-AppIcon

# Create the main form
$Form = [System.Windows.Forms.Form]::new()
$Form.Text = "EliteSoftware HTTP Test Server"
$Form.Size = [System.Drawing.Size]::new($FormWidth, $FormHeight)
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Form.MinimizeBox = $true
$Form.MaximizeBox = $false
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.BackColor = [System.Drawing.Color]::FromArgb(255, 240, 240, 240) # Light grey background
$Form.Icon = $AppIcon

# --- Menu Strip (Top) ---
$MenuStrip = [System.Windows.Forms.MenuStrip]::new()
$MenuStrip.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220, 220) # Light Gray

# File Menu
$FileMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("File")
$NewMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("New Server Configuration")
$SettingsMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Settings...")
$ExitMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Exit")

$FileMenuItem.DropDownItems.Add($NewMenuItem) | Out-Null
$FileMenuItem.DropDownItems.Add("-") | Out-Null
$FileMenuItem.DropDownItems.Add($SettingsMenuItem) | Out-Null
$SettingsMenuItem.Add_Click({ Show-SettingsWindow })
$FileMenuItem.DropDownItems.Add("-") | Out-Null
$FileMenuItem.DropDownItems.Add($ExitMenuItem) | Out-Null
$MenuStrip.Items.Add($FileMenuItem) | Out-Null

# Help Menu
$HelpMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Help")
$ViewHelpMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("View Help Guide")
$ViewHelpMenuItem.Add_Click({ Show-HelpGuideWindow })
$HelpMenuItem.DropDownItems.Add($ViewHelpMenuItem) | Out-Null
$MenuStrip.Items.Add($HelpMenuItem) | Out-Null


$Form.Controls.Add($MenuStrip)

# --- Sidebar Panel (Left) ---
$SidebarPanel = [System.Windows.Forms.Panel]::new()
$SidebarPanel.Dock = [System.Windows.Forms.DockStyle]::Left
$SidebarPanel.Width = $SidebarWidth
$SidebarPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220, 220) # Light Gray sidebar
$Form.Controls.Add($SidebarPanel)

$SidebarTitle = [System.Windows.Forms.Label]::new()
$SidebarTitle.Text = "Server Configurations"
$SidebarTitle.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$SidebarTitle.AutoSize = $true
$SidebarTitle.Location = [System.Drawing.Point]::new(10, 5)
$SidebarPanel.Controls.Add($SidebarTitle)

$SidebarList = [System.Windows.Forms.ListBox]::new()
$SidebarList.Location = [System.Drawing.Point]::new(10, 30)
$SidebarList.Width = $SidebarWidth - 20
$SidebarList.Height = $FormHeight - 100
$SidebarList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left

# Populate sidebar list
$Script:ServerConfigs | ForEach-Object {
    [void]$SidebarList.Items.Add($_.Name)
}

$SidebarPanel.Controls.Add($SidebarList)

# Sidebar selection change handler
$SidebarList.Add_SelectedIndexChanged({
    Update-ConfigFromGUI # Save the old config before changing
    $Script:CurrentConfigIndex = $SidebarList.SelectedIndex
    Update-GUIFromConfig # Load the new config
    Write-Log "Configuration loaded: $($Script:ServerConfigs[$Script:CurrentConfigIndex].Name)"
})
# Select the first item initially
if ($SidebarList.Items.Count -gt 0) {
    $SidebarList.SelectedIndex = 0
}

# --- Context Menu for Sidebar ---
$SidebarContextMenu = [System.Windows.Forms.ContextMenuStrip]::new()

$DuplicateMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Duplicate Configuration")
$RenameMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Rename Configuration")
$StartServerMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Start Server")
$StopServerMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new("Stop Server")

$SidebarContextMenu.Items.Add($DuplicateMenuItem) | Out-Null
$SidebarContextMenu.Items.Add($RenameMenuItem) | Out-Null
$SidebarContextMenu.Items.Add("-") | Out-Null # Separator
$SidebarContextMenu.Items.Add($StartServerMenuItem) | Out-Null
$SidebarContextMenu.Items.Add($StopServerMenuItem) | Out-Null

$SidebarList.ContextMenuStrip = $SidebarContextMenu

# Tooltip for sidebar items
$SidebarToolTip = [System.Windows.Forms.ToolTip]::new()
$SidebarToolTip.InitialDelay = 500
$SidebarToolTip.ReshowDelay = 500
$SidebarToolTip.AutoPopDelay = 5000

$SidebarList.Add_MouseMove({
    param($sender, $e)
    $index = $sender.IndexFromPoint($e.Location)
    if ($index -ge 0 -and $index -lt $Script:ServerConfigs.Count) {
        $config = $Script:ServerConfigs[$index]
        $tooltipText = "URL: http://$($config.IP):$($config.Port)/`nRoot: $($config.Root)"
        if ($SidebarToolTip.GetToolTip($sender) -ne $tooltipText) {
            $SidebarToolTip.SetToolTip($sender, $tooltipText)
        }
    } else {
        $SidebarToolTip.SetToolTip($sender, "")
    }
})

# --- Main Content Panel (Right) ---
$ContentPanel = [System.Windows.Forms.Panel]::new()
$ContentPanel.Location = [System.Drawing.Point]::new($SidebarWidth, $MenuStrip.Height)
$ContentPanel.Width = $FormWidth - $SidebarWidth
$ContentPanel.Height = $FormHeight - $MenuStrip.Height
$Form.Controls.Add($ContentPanel)

# Create Header Panel
$HeaderPanel = [System.Windows.Forms.Panel]::new()
$HeaderPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$HeaderPanel.Height = 70
$HeaderPanel.Add_Paint({Draw-GradientHeader $HeaderPanel $_}) # Attach the custom draw function
$ContentPanel.Controls.Add($HeaderPanel)

# Header Title
$HeaderLabel = [System.Windows.Forms.Label]::new()
$HeaderLabel.Text = "HTTP Test Server Control Panel"
$HeaderLabel.Font = [System.Drawing.Font]::new("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$HeaderLabel.ForeColor = [System.Drawing.Color]::White
$HeaderLabel.AutoSize = $true
$HeaderLabel.Location = [System.Drawing.Point]::new(20, 20)
$HeaderLabel.BackColor = [System.Drawing.Color]::Transparent
$HeaderPanel.Controls.Add($HeaderLabel)

# --- Auto-Start Checkbox ---
$yPos = 80
$AutoStartCheckBox = [System.Windows.Forms.CheckBox]::new()
$AutoStartCheckBox.Text = "Auto-Start This Server on Launch"
$AutoStartCheckBox.AutoSize = $true
$AutoStartCheckBox.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$AutoStartCheckBox.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($AutoStartCheckBox)
$yPos += 30

# --- Mode Selection Checkbox ---
$RootModeCheckBox = [System.Windows.Forms.CheckBox]::new()
$RootModeCheckBox.Text = "Use Root Folder Mode"
$RootModeCheckBox.AutoSize = $true
$RootModeCheckBox.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$RootModeCheckBox.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($RootModeCheckBox)
$yPos += 35 # Increased spacing

# --- Server Root Folder Controls (Root Mode) ---
$RootLabel = [System.Windows.Forms.Label]::new()
$RootLabel.Text = "Server Root Folder:"
$RootLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$RootLabel.AutoSize = $true
$RootLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($RootLabel)

$RootTextBox = [System.Windows.Forms.TextBox]::new()
$RootTextBox.Width = 320
$RootTextBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($RootTextBox)

$BrowseButton = [System.Windows.Forms.Button]::new()
$BrowseButton.Text = "Browse..."
$BrowseButton.Width = 100
$BrowseButton.Height = 25
$BrowseButton.Location = [System.Drawing.Point]::new(([int]$xStart + 330), ($yPos + 25))
$BrowseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($BrowseButton)

# --- Single HTML File Controls (Single File Mode) ---
$SingleFileLabel = [System.Windows.Forms.Label]::new()
$SingleFileLabel.Text = "Single HTML File to Serve:"
$SingleFileLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$SingleFileLabel.AutoSize = $true
$SingleFileLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($SingleFileLabel)

$SingleFileTextBox = [System.Windows.Forms.TextBox]::new()
$SingleFileTextBox.Width = 320
$SingleFileTextBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($SingleFileTextBox)

$SingleFileBrowseButton = [System.Windows.Forms.Button]::new()
$SingleFileBrowseButton.Text = "Browse..."
$SingleFileBrowseButton.Width = 100
$SingleFileBrowseButton.Height = 25
$SingleFileBrowseButton.Location = [System.Drawing.Point]::new(([int]$xStart + 330), ($yPos + 25))
$SingleFileBrowseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($SingleFileBrowseButton)


# --- Default File Name Controls ---
$yPos += 60 # Corrected Y position
$DefaultFileLabel = [System.Windows.Forms.Label]::new()
$DefaultFileLabel.Text = "Default File Name (e.g., index.html):"
$DefaultFileLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$DefaultFileLabel.AutoSize = $true
$DefaultFileLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($DefaultFileLabel)

$DefaultFileTextBox = [System.Windows.Forms.TextBox]::new()
$DefaultFileTextBox.Width = 250
$DefaultFileTextBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($DefaultFileTextBox)


# --- Port Controls ---
$PortLabel = [System.Windows.Forms.Label]::new()
$PortLabel.Text = "Server Port:"
$PortLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$PortLabel.AutoSize = $true
$PortLabel.Location = [System.Drawing.Point]::new(([int]$xStart + 280), $yPos) # Adjusted X
$ContentPanel.Controls.Add($PortLabel)

$PortTextBox = [System.Windows.Forms.TextBox]::new()
$PortTextBox.Text = "8080"
$PortTextBox.Width = 80
$PortTextBox.Location = [System.Drawing.Point]::new(([int]$xStart + 280), ($yPos + 25)) # Adjusted X
$ContentPanel.Controls.Add($PortTextBox)

# --- IP Address Selection ---
$yPos += 60 # Corrected Y position
$IPLabel = [System.Windows.Forms.Label]::new()
$IPLabel.Text = "IP Address to Bind:"
$IPLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$IPLabel.AutoSize = $true
$IPLabel.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$ContentPanel.Controls.Add($IPLabel)

$IPComboBox = [System.Windows.Forms.ComboBox]::new()
$IPComboBox.Width = 320
$IPComboBox.DropDownHeight = 150
$IPComboBox.Items.AddRange((Get-LocalIPv4Addresses))

$IPComboBox.Location = [System.Drawing.Point]::new([int]$xStart, ($yPos + 25))
$ContentPanel.Controls.Add($IPComboBox)


# --- Action Buttons with Colored Border Panels ---
$yPos += 70 # Corrected Y position

# 1. Start Button
$StartButton = [System.Windows.Forms.Button]::new()
$StartButton.Text = "Start Server"
$StartButton.Width = $ButtonWidth
$StartButton.Height = $ButtonHeight
$StartButton.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$StartButton.Location = [System.Drawing.Point]::new([int]$xStart, $yPos)
$StartButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($StartButton)

# 2. Stop Button
$StopButton = [System.Windows.Forms.Button]::new()
$StopButton.Text = "Stop Server"
$StopButton.Width = $ButtonWidth
$StopButton.Height = $ButtonHeight
$StopButton.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$StopButton.Location = [System.Drawing.Point]::new(([int]$xStart + $ButtonWidth + 20), $yPos)
$StopButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($StopButton)

# 3. Open in Browser Button
$OpenBrowserButton = [System.Windows.Forms.Button]::new()
$OpenBrowserButton.Text = "Open in Browser"
$OpenBrowserButton.Width = $ButtonWidth
$OpenBrowserButton.Height = $ButtonHeight
$OpenBrowserButton.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$OpenBrowserButton.Location = [System.Drawing.Point]::new(([int]$xStart + 2*($ButtonWidth + 20)), $yPos)
$OpenBrowserButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($OpenBrowserButton)


# --- Status Log (Adjusted for Content Panel) ---
$LogTextBox = [System.Windows.Forms.TextBox]::new()
$LogTextBox.Width = $ContentWidth - 2 * $xStart
$LogTextBox.Height = 100
$LogTextBox.Multiline = $true
$LogTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$LogTextBox.ReadOnly = $true
$LogTextBox.BackColor = [System.Drawing.Color]::Black
$LogTextBox.ForeColor = [System.Drawing.Color]::Lime
# Y position adjusted relative to ContentPanel
$LogTextBox.Location = [System.Drawing.Point]::new([int]$xStart, $yPos + $ButtonHeight + 20) # Position below buttons
$ContentPanel.Controls.Add($LogTextBox)


# --- Exit Button (REQUESTED) ---
$ExitButton = [System.Windows.Forms.Button]::new()
$ExitButton.Text = "Exit"
$ExitButton.Width = 60
$ExitButton.Height = 25
$ExitButton.Location = [System.Drawing.Point]::new($ContentWidth - 60 - $xStart, $LogTextBox.Location.Y + $LogTextBox.Height + 15) # Position below log box
$ExitButton.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$ContentPanel.Controls.Add($ExitButton)

# Tooltip for Exit Button
$ExitTooltip = [System.Windows.Forms.ToolTip]::new()
$ExitTooltip.SetToolTip($ExitButton, "Gracefully stop all active servers before closing the window.")

# --- Main Control Tooltips ---
$MainTooltip = [System.Windows.Forms.ToolTip]::new()
$MainTooltip.SetToolTip($RootModeCheckBox, "Check this to serve files from a directory. Uncheck to serve a single file.")
$MainTooltip.SetToolTip($RootTextBox, "The root directory your website files are in (Root Folder Mode).")
$MainTooltip.SetToolTip($SingleFileTextBox, "The single HTML file to serve for all requests (Single File Mode).")
$MainTooltip.SetToolTip($DefaultFileTextBox, "The default file to serve for root requests, e.g., 'index.html' (Root Folder Mode).")
$MainTooltip.SetToolTip($PortTextBox, "The network port the server will listen on (e.g., 8080).")
$MainTooltip.SetToolTip($IPComboBox, "The IP address the server will bind to. 127.0.0.1 is for local access only.")
$MainTooltip.SetToolTip($StartButton, "Starts the server with the current configuration.")
$MainTooltip.SetToolTip($StopButton, "Stops the currently running server.")
$MainTooltip.SetToolTip($OpenBrowserButton, "Opens the server URL in your default browser.")
$MainTooltip.SetToolTip($LogTextBox, "Displays live server activity, requests, and errors.")
$MainTooltip.SetToolTip($AutoStartCheckBox, "If checked, this server will attempt to start automatically when the application launches.")


# --- Status Bar ---

$StatusBar = [System.Windows.Forms.StatusStrip]::new()
$StatusBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$StatusBar.SizingGrip = $false
$StatusBar.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 220, 220)

$CompanyLabel = [System.Windows.Forms.ToolStripStatusLabel]::new()
$CompanyLabel.Text = "EliteSoftware"
$CompanyLabel.Spring = $true
$CompanyLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$StatusBar.Items.Add($CompanyLabel) | Out-Null

$VersionLabel = [System.Windows.Forms.ToolStripStatusLabel]::new()
$VersionLabel.Text = "Version: $ScriptVersion"
$VersionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$StatusBar.Items.Add($VersionLabel) | Out-Null

$StatusIndicator = [System.Windows.Forms.ToolStripStatusLabel]::new()
$StatusIndicator.Text = "Status: Stopped"
$StatusIndicator.ForeColor = [System.Drawing.Color]::Red
$StatusBar.Items.Add($StatusIndicator) | Out-Null

$Form.Controls.Add($StatusBar)

# ==============================================================================
# 6. Event Handling and Main Loop
# ==============================================================================

$StartButton.Add_Click({
    Update-ConfigFromGUI
    $currentConfig = $Script:ServerConfigs[$Script:CurrentConfigIndex]
    
    if ($Script:ActiveServers.ContainsKey($currentConfig.Name)) {
        Write-Log "Server '$($currentConfig.Name)' is already running."
        return
    }
    
    # Check for root path existence
    if ($currentConfig.UseRootFolderMode -and -not (Test-Path $currentConfig.Root -PathType Container)) {
        Write-Log "ERROR: Server Root Path not found: $($currentConfig.Root)"
        return
    }

    # Check for single file existence
    if (-not $currentConfig.UseRootFolderMode -and -not (Test-Path $currentConfig.SingleFilePath -PathType Leaf)) {
        Write-Log "ERROR: Single HTML file not found: $($currentConfig.SingleFilePath)"
        return
    }

    Start-Server $currentConfig
})

$StopButton.Add_Click({
    $currentConfig = $Script:ServerConfigs[$Script:CurrentConfigIndex]
    Stop-Server $currentConfig
})

$BrowseButton.Add_Click({
    $FolderBrowser = [System.Windows.Forms.FolderBrowserDialog]::new()
    $FolderBrowser.SelectedPath = $RootTextBox.Text
    if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $RootTextBox.Text = $FolderBrowser.SelectedPath
        Update-ConfigFromGUI
        Write-Log "Root folder set to: $($RootTextBox.Text)"
    }
})

$SingleFileBrowseButton.Add_Click({
    $FileBrowser = [System.Windows.Forms.OpenFileDialog]::new()
    $FileBrowser.Filter = "HTML Files (*.html, *.htm)|*.html;*.htm|All files (*.*)|*.*"
    if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $SingleFileTextBox.Text = $FileBrowser.FileName
        Update-ConfigFromGUI
        Write-Log "Single file set to: $($SingleFileTextBox.Text)"
    }
})

$RootModeCheckBox.Add_CheckedChanged({
    Update-ConfigFromGUI
    Update-GUIFromConfig
})

$OpenBrowserButton.Add_Click({
    $currentConfig = $Script:ServerConfigs[$Script:CurrentConfigIndex]
    if ($currentConfig.Status -eq "Running") {
        $prefix = $Script:ActiveServers[$currentConfig.Name].Prefix
        $startUrl = $prefix.TrimEnd('/') # Use the actual running prefix
        [void][System.Diagnostics.Process]::Start($startUrl)
        Write-Log "Opening $startUrl in default browser."
    } else {
        Write-Log "Cannot open browser: Server is not running."
    }
})

$NewMenuItem.Add_Click({
    Add-NewConfig
    $SidebarList.Items.Add($Script:ServerConfigs[-1].Name) | Out-Null
    $SidebarList.SelectedIndex = $Script:ServerConfigs.Count - 1
})

$ExitButton.Add_Click({
    $Form.Close() # This triggers FormClosing event
})

$ExitMenuItem.Add_Click({
    $Form.Close() # This triggers FormClosing event
})

# IMPORTANT: A SINGLE FormClosing handler for orderly shutdown
$Form.Add_FormClosing({
    param($sender, $e)

    # Prevent the form from closing immediately while we show the goodbye message
    if (-not $Script:IsExiting) {
        $e.Cancel = $true # Always cancel the first close event to allow for graceful shutdown

        # 1. Signal all background threads to stop
        $Script:IsExiting = $true

        # 2. Stop all running servers gracefully
        $Script:ServerConfigs | Where-Object { $_.Status -eq "Running" } | ForEach-Object {
            Stop-Server $_
        }

        # 3. Stop the log timer
        if ($Script:LogTimer -and $Script:LogTimer.Enabled) {
            $Script:LogTimer.Stop()
        }

        # 4. Show goodbye window or close immediately
        if ($Script:Settings.ShowGoodbyeWindow) {
            Show-GoodbyeWindow "Goodbye see you soon!"
        } else {
            # This will re-trigger FormClosing, but $Script:IsExiting is now true, so it will fall through
            $Form.Close()
        }
    }
    # On the second pass (triggered by Show-GoodbyeWindow or immediate close), $Script:IsExiting is true, and the form closes without canceling.
})

$DuplicateMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $originalConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        $newConfig = $originalConfig | Select-Object * # Easiest way to clone a PSCustomObject
        $newConfig.Name = "$($originalConfig.Name) (Copy)"
        $newConfig.Port = $originalConfig.Port + 1 # Suggest a new port
        $newConfig.Status = "Stopped"
        
        $Script:ServerConfigs += $newConfig
        $SidebarList.Items.Add($newConfig.Name) | Out-Null
        Save-ServerConfig
        Write-Log "Duplicated configuration: $($newConfig.Name)"
    }
})

$RenameMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $currentConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        $inputBox = [Microsoft.VisualBasic.Interaction]::InputBox("Enter new name for configuration:", "Rename Configuration", $currentConfig.Name)
        if (-not [string]::IsNullOrEmpty($inputBox)) {
            $currentConfig.Name = $inputBox
            $SidebarList.Items[$SidebarList.SelectedIndex] = $inputBox
            Save-ServerConfig
            Update-GUIFromConfig # Update header if current config is renamed
            Write-Log "Renamed configuration to: $($inputBox)"
        }
    }
})

$StartServerMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $currentConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        if ($currentConfig.Status -ne "Running") {
            Start-Server $currentConfig
        } else {
            Write-Log "Server '$($currentConfig.Name)' is already running."
        }
    }
})

$StopServerMenuItem.Add_Click({
    if ($SidebarList.SelectedIndex -ge 0) {
        $currentConfig = $Script:ServerConfigs[$SidebarList.SelectedIndex]
        if ($currentConfig.Status -eq "Running") {
            Stop-Server $currentConfig
        } else {
            Write-Log "Server '$($currentConfig.Name)' is not running."
        }
    }
})

# --- Final Initialization ---
# This handler runs when the form is fully loaded and the handle is created
$Form.Add_Shown({
    # 1. Update the GUI with the initially selected config
    Update-GUIFromConfig

    # 2. Auto-start servers that are configured to do so
    $autoStartConfigs = $Script:ServerConfigs | Where-Object { $_.AutoStart -eq $true }
    if ($autoStartConfigs) {
        Write-Log "Found $($autoStartConfigs.Count) server(s) configured for auto-start..."
        foreach ($config in $autoStartConfigs) {
            Write-Log "Auto-starting server: $($config.Name)"
            Start-Server $config
        }
    }
})

Start-LogTimer
Write-Log "EliteSoftware HTTP Test Server v$ScriptVersion Initialized."

# Main loop to show the form
$Form.ShowDialog() | Out-Null

# Minimize the console window upon running
$consoleHandle = (Get-Host).UI.RawUI.Handle
[Runtime.InteropServices.Marshal]::PtrToStructure($consoleHandle, [Type]'System.ConsoleScreenBufferInfo').dwSize | Out-Null
$consoleHandle = (Get-Host).UI.RawUI.Handle
$coords = [System.Management.Automation.Host.Coordinates]::new(0, 0)
(Get-Host).UI.RawUI.SetWindowPosition($coords)
(Get-Host).UI.RawUI.WindowSize = [System.Management.Automation.Host.Size]::new(1, 1)