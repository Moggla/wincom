param (
    [Parameter(Position = 0)]
    [string]$Argument = "",
    [switch]$WriteMode,
    [switch]$ShowDirection,
    [switch]$NoExit,
    [switch]$AutoConnect,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ConnectRate = 2000,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$RefreshRate = 20,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$BaudRate = 115200,
    [ValidateSet('None', 'Odd', 'Even', 'Mark', 'Space')]
    [string]$Parity = 'None',
    [ValidateRange(5, 8)]
    [int]$DataBits = 8,
    [ValidateSet('One', 'OnePointFive', 'Two')]
    [string]$StopBits = 'One',
    [ValidateSet('LF', 'CR', 'CRLF', 'None')]
    [string]$LineEnding = 'LF',
    [ValidateSet('UTF8', 'ASCII', 'Latin1')]
    [string]$Encoding = 'UTF8',
    [switch]$Dtr,
    [switch]$Rts,
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
  -Parity <string>       None, Odd, Even, Mark or Space [default: None]
  -DataBits <int>        5 to 8 [default: 8]
  -StopBits <string>     One, OnePointFive or Two [default: One]
  -LineEnding <string>   LF, CR, CRLF or None appended when sending [default: LF]
  -Encoding <string>     UTF8, ASCII or Latin1 [default: UTF8]
  -Dtr                   Enable DTR (needed by many USB CDC devices)
  -Rts                   Enable RTS
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
if ($Argument -and $Argument -notmatch '^COM\d+$') {
    Write-Warning "Invalid argument: $Argument"
    Show-Help; return
}
$Argument = $Argument.ToUpper()
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
$script:Terminator    = @{ LF = "`n"; CR = "`r"; CRLF = "`r`n"; None = "" }[$LineEnding]
$script:TextEncoding  = switch ($Encoding) {
    'UTF8'   { [Text.UTF8Encoding]::new($false) }
    'ASCII'  { [Text.Encoding]::ASCII }
    'Latin1' { [Text.Encoding]::GetEncoding(28591) }
}
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

function Write-LinePrefix([string]$Direction) {
    if ($ShowDirection) { Write-Host "$Direction " -NoNewline }
}

function Write-Rx([string]$data) {
    Hide-Prompt
    # Data arrives in arbitrary chunks, so the prefix goes in front of each line.
    foreach ($part in $data -split '(?<=\n)') {
        if (-not $part) { continue }
        if ($script:AtLineStart) { Write-LinePrefix "<<" }
        Write-Host $part -NoNewline
        $script:AtLineStart = $part.EndsWith("`n")
    }
    Show-Prompt
}

function Write-Tx([string]$text) {
    Hide-Prompt
    if (-not $script:AtLineStart) { Write-Host "" }
    Write-LinePrefix ">>"
    Write-Host $text
    $script:AtLineStart = $true
    Show-Prompt
}

function Submit-Input($sp) {
    $msg = $script:InputBuffer.ToString()
    [void]$script:InputBuffer.Clear()
    Hide-Prompt
    $sp.Write($msg + $script:Terminator)
    if ($msg -and ($script:History.Count -eq 0 -or $script:History[-1] -ne $msg)) { $script:History.Add($msg) }
    Write-Tx $msg
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

function Get-ErrorMessage($ErrorRecord) {
    # Unwrap 'Exception calling "Open" with "0" argument(s)' to the actual reason.
    $exception = $ErrorRecord.Exception
    while ($exception.InnerException) { $exception = $exception.InnerException }
    $exception.Message
}

function Write-Status([string]$Message, [switch]$Warning) {
    Hide-Prompt
    if (-not $script:AtLineStart) {
        Write-Host ""
        $script:AtLineStart = $true
    }
    if ($Warning) { Write-Warning $Message }
    else          { Write-Host $Message }
    Show-Prompt
}

function Connect-Port {
    $waiting = $false
    while (-not $script:ExitRequested) {
        $sp = [System.IO.Ports.SerialPort]::new($Argument, $BaudRate, $Parity, $DataBits, $StopBits)
        $sp.Encoding  = $script:TextEncoding
        $sp.ReadTimeout = 200
        $sp.DtrEnable = $Dtr
        $sp.RtsEnable = $Rts

        try {
            $sp.Open()
        }
        catch {
            $sp.Dispose()
            if (-not $AutoConnect) {
                Write-Status (Get-ErrorMessage $_) -Warning
                return
            }
            if (-not $waiting) {
                Write-Status "Waiting for $Argument ($(Get-ErrorMessage $_))"
                $waiting = $true
            }
            Wait-Interruptible $ConnectRate
            continue
        }

        $waiting = $false
        $info = "Opened $Argument @ $BaudRate baud."
        if ($WriteMode) { $info += " Type and Enter to send." }
        else            { $info += " Read-only." }
        if ($NoExit -and $WriteMode) { $info += " Ctrl+C is sent to the device." }
        if ($script:Interactive)     { $info += " Ctrl+Q to quit." }
        Write-Status "$info`n"

        try {
            while (-not $script:ExitRequested) {
                if ($sp.BytesToRead -gt 0) {
                    $data = $sp.ReadExisting()
                    if ($data) { Write-Rx $data }
                }

                Read-Keys $sp
                Start-Sleep -Milliseconds $RefreshRate
            }
        }
        catch {
            # Unplugging a USB adapter does not clear IsOpen, it makes reads and writes throw.
            Write-Status "Serial port disconnected ($(Get-ErrorMessage $_))" -Warning
        }
        finally {
            try { $sp.Close() } catch { }
            $sp.Dispose()
        }
        Write-Status "Closed $Argument"

        # With -AutoConnect the next iteration waits until the port is back.
        if (-not $AutoConnect) { return }
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
