param (
    [Parameter(Position = 0)]
    [string]$Argument = "",
    [switch]$WriteMode,
    [switch]$ShowDirection,
    [switch]$NoExit,
    [switch]$AutoConnect,
    [int]$ConnectRate = 2000,
    [int]$RefreshRate = 20,
    [int]$BaudRate = 115200,
    [string]$Parity = 'None',
    [int]$DataBits = 8,
    [string]$StopBits = 'One',
    [switch]$Help,
    [switch]$Version
)

function Show-Help {
    @"

Description:
  wincom - lightweight serial terminal

Usage:
  wincom <argument> [options]

Arguments:
  COM[N]                 e.g. COM3
  list                   Show available serial ports

Options:
  -WriteMode             Enable read & write mode
  -ShowDirection         Show << / >> for RX / TX
  -NoExit                Do not quit on Ctrl+C (sent to the device in write mode)
  -AutoConnect           Automatically connect to serial port
  -ConnectRate <int>     AutoConnect rate in milliseconds [default: 2000]
  -RefreshRate <int>     Refresh rate in milliseconds [default: 20]
  -BaudRate <int>        Baud rate [default: 115200]
  -Parity <string>       Parity [default: None]
  -DataBits <int>        Data bits [default: 8]
  -StopBits <string>     Stop bits [default: One]
  -Version               Show version information
  -Help                  Show help and usage information

Keys:
  Ctrl+Q                 Quit
  Ctrl+C                 Quit (sent to the device with -NoExit -WriteMode)
  Enter / Esc            Send / clear the current input
  Up / Down              Browse previously sent input

"@ | Write-Host
}

function Show-Version {
    Write-Host "wincom version 0.0.1"
}

if ($Help) {
    Show-Help; return
}
if ($Version) {
    Show-Version; return
}
function Get-SerialPorts {
    # Win32_SerialPort misses many USB CDC devices, so enumerate the port names
    # and look up descriptions from the PnP devices.
    $devices = @(Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%(COM%'" -ErrorAction SilentlyContinue)
    $names = [System.IO.Ports.SerialPort]::GetPortNames() |
      ForEach-Object { $_ -replace '[^\w]', '' } |
      Where-Object { $_ -match '^COM\d+$' } |
      Sort-Object -Unique |
      Sort-Object { [int]($_ -replace '\D', '') }

    foreach ($name in $names) {
        $device = $devices | Where-Object { $_.Name -match "\($name\)" } | Select-Object -First 1
        $vidPid = ''
        if ($device.PNPDeviceID -match 'VID_([0-9A-F]{4}).*PID_([0-9A-F]{4})') {
            $vidPid = "$($Matches[1]):$($Matches[2])"
        }
        [PSCustomObject]@{
            Port        = $name
            Description = if ($device) { $device.Name -replace '\s*\(COM\d+\)$', '' } else { '' }
            'VID:PID'   = $vidPid
        }
    }
}

if ($Argument -eq "list") {
    $ports = @(Get-SerialPorts)
    if (-not $ports) {
        Write-Warning "No COM ports found."
        return
    }
    $ports | Format-Table -AutoSize
    return
}
if (-not $Argument) {
    $Argument = Get-SerialPorts | Select-Object -First 1 -ExpandProperty Port
    if (-not $Argument) {
        Write-Warning "Missing or invalid argument."
        Show-Help; return
    } else {
        Write-Warning "Missing argument. Opening first available port: $Argument"
    }
}

$script:Interactive   = -not [Console]::IsInputRedirected
$script:ExitRequested = $false
$script:AtLineStart   = $true
$script:InputBuffer   = [System.Text.StringBuilder]::new()
$script:PromptShown   = $false
$script:History       = [System.Collections.Generic.List[string]]::new()
$script:HistoryIndex  = 0

function Get-ConsoleWidth {
    try { [Console]::BufferWidth } catch { 80 }
}

function Hide-Prompt {
    if (-not $script:PromptShown) { return }
    Write-Host ("`r" + (' ' * ((Get-ConsoleWidth) - 1)) + "`r") -NoNewline
    $script:PromptShown = $false
}

function Show-Prompt {
    if (-not $WriteMode -or $script:InputBuffer.Length -eq 0) { return }
    # The prompt needs its own line, otherwise hiding it would erase received text.
    if (-not $script:AtLineStart) {
        Write-Host ""
        $script:AtLineStart = $true
    }
    $prefix = if ($ShowDirection) { ">> " } else { "" }
    $text = $script:InputBuffer.ToString()
    $max = (Get-ConsoleWidth) - 1 - $prefix.Length
    if ($text.Length -gt $max) { $text = "..." + $text.Substring($text.Length - $max + 3) }
    Write-Host ($prefix + $text) -NoNewline
    $script:PromptShown = $true
}

function Write-Rx([string]$data) {
    Hide-Prompt
    if ($ShowDirection) { $data = "<< $data" }
    Write-Host $data -NoNewline
    $script:AtLineStart = $data.EndsWith("`n")
    Show-Prompt
}

function Write-Tx([string]$text) {
    Hide-Prompt
    if (-not $script:AtLineStart) { Write-Host "" }
    if ($ShowDirection) { $text = ">> $text" }
    Write-Host $text
    $script:AtLineStart = $true
    Show-Prompt
}

function Submit-Input($sp) {
    $msg = $script:InputBuffer.ToString()
    [void]$script:InputBuffer.Clear()
    Hide-Prompt
    if ($msg.Trim() -ne "") {
        $sp.WriteLine($msg.Trim())
        $script:History.Add($msg)
        Write-Tx $msg.Trim()
    }
    $script:HistoryIndex = $script:History.Count
}

function Read-Keys($sp) {
    # Keys are read without blocking so received data keeps flowing while typing.
    if (-not $script:Interactive) { return }
    while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)

        if ($key.KeyChar -eq [char]0x11) {          # Ctrl+Q
            $script:ExitRequested = $true
            return
        }
        if ($key.KeyChar -eq [char]0x03) {          # Ctrl+C
            if (-not $NoExit) {
                $script:ExitRequested = $true
                return
            }
            if ($WriteMode -and $sp) {
                $sp.Write([byte[]]@(3), 0, 1)
                Write-Tx "^C"
            }
            continue
        }
        if (-not $WriteMode -or -not $sp) { continue }

        Hide-Prompt
        if ($key.Key -eq [ConsoleKey]::Enter) {
            Submit-Input $sp
        } elseif ($key.Key -eq [ConsoleKey]::Backspace) {
            if ($script:InputBuffer.Length -gt 0) { [void]$script:InputBuffer.Remove($script:InputBuffer.Length - 1, 1) }
        } elseif ($key.Key -eq [ConsoleKey]::Escape) {
            [void]$script:InputBuffer.Clear()
        } elseif ($key.Key -eq [ConsoleKey]::UpArrow -or $key.Key -eq [ConsoleKey]::DownArrow) {
            if ($key.Key -eq [ConsoleKey]::UpArrow) { $script:HistoryIndex = [Math]::Max(0, $script:HistoryIndex - 1) }
            else { $script:HistoryIndex = [Math]::Min($script:History.Count, $script:HistoryIndex + 1) }
            [void]$script:InputBuffer.Clear()
            if ($script:HistoryIndex -lt $script:History.Count) { [void]$script:InputBuffer.Append($script:History[$script:HistoryIndex]) }
        } elseif ($key.KeyChar -ge [char]0x20 -and $key.KeyChar -ne [char]0x7F) {
            [void]$script:InputBuffer.Append($key.KeyChar)
        }
        Show-Prompt
    }
}

function Wait-Interruptible([int]$Milliseconds) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    while (-not $script:ExitRequested -and [DateTime]::UtcNow -lt $deadline) {
        Read-Keys $null
        Start-Sleep -Milliseconds ([Math]::Min(50, $Milliseconds))
    }
}

function Connect-Port {
    while (-not $script:ExitRequested) {
        $sp = [System.IO.Ports.SerialPort]::new($Argument, $BaudRate, $Parity, $DataBits, $StopBits)
        $sp.Encoding  = [Text.Encoding]::ASCII
        $sp.NewLine   = "`n"
        $sp.ReadTimeout = 200

        try {
            $sp.Open()
            Write-Host "Opened $Argument @ $BaudRate baud. " -NoNewline
            if ($WriteMode) { Write-Host "Type and Enter to send. " -NoNewline }
            else            { Write-Host "Read-only. " -NoNewline }
            if ($NoExit -and $WriteMode) { Write-Host "Ctrl+C is sent to the device. " -NoNewline }
            if ($script:Interactive) { Write-Host "Ctrl+Q to quit.`n" }
            else                     { Write-Host "`n" }

            while (-not $script:ExitRequested) {
                if (-not $sp.IsOpen) {
                    Write-Warning "Serial port disconnected."
                    break
                }

                if ($sp.BytesToRead -gt 0) {
                    $data = $sp.ReadExisting()
                    if ($data) { Write-Rx $data }
                }

                Read-Keys $sp
                Start-Sleep -Milliseconds $RefreshRate
            }
        }
        catch {
            if ($AutoConnect) {
                Wait-Interruptible $ConnectRate
                continue
            } else {
                Hide-Prompt
                Write-Warning "$_"
                break
            }
        }
        finally {
            if ($sp.IsOpen) {
                $sp.Close()
                Hide-Prompt
                Write-Host "`nClosed $Argument"
            }
        }
        if ($AutoConnect) {
            Wait-Interruptible $ConnectRate
            continue
        }
        break
    }
}

# Ctrl+C is handled in Read-Keys so the port is always closed cleanly.
if ($script:Interactive) {
    $treatControlCAsInput = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true
}
try {
    Connect-Port
}
finally {
    if ($script:Interactive) { [Console]::TreatControlCAsInput = $treatControlCAsInput }
}
