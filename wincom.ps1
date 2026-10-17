param (
    [Parameter(Position = 0)]
    [string]$Argument = "",
    [switch]$WriteMode,
    [switch]$ShowDirection,
    [switch]$NoExit,
    [switch]$AutoConnect,
    [int]$ConnectRate = 2000,
    [int]$RefreshRate = 100,
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
  -NoExit                Disable Ctrl+C to exit
  -AutoConnect           Automatically connect to serial port
  -ConnectRate <int>     AutoConnect rate in milliseconds [default: 2000]
  -RefreshRate <int>     Refresh rate in milliseconds [default: 100]
  -BaudRate <int>        Baud rate [default: 115200]
  -Parity <string>       Parity [default: None]
  -DataBits <int>        Data bits [default: 8]
  -StopBits <string>     Stop bits [default: One]
  -Version               Show version information
  -Help                  Show help and usage information

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
if ($NoExit) { [Console]::TreatControlCAsInput = $true }
else         { [Console]::TreatControlCAsInput = $false }

function Connect-Port {
    while ($true) {
        $sp = [System.IO.Ports.SerialPort]::new($Argument, $BaudRate, $Parity, $DataBits, $StopBits)
        $sp.Encoding  = [Text.Encoding]::ASCII
        $sp.NewLine   = "`n"
        $sp.ReadTimeout = 200

        try {
            $sp.Open()
            Write-Host "Opened $Argument @ $BaudRate baud. " -NoNewline
            if ($WriteMode) { 
                if ($NoExit){ Write-Host "Type and Enter TWICE to send. " -NoNewline }
                else        { Write-Host "Type and Enter to send. " -NoNewline }
            }
            else            { Write-Host "Read-only. " -NoNewline }
            if ($NoExit)    { Write-Host "No keyboard shortcut to quit.`n" }
            else            { Write-Host "Ctrl+C to quit.`n" }

            while ($true) {
                if (-not $sp.IsOpen) {
                    Write-Warning "Serial port disconnected."
                    break
                }

                if ($sp.BytesToRead -gt 0) {
                    $data = $sp.ReadExisting()
                    if ($data) {
                        if ($ShowDirection) {
                            Write-Host "<< $data" -NoNewline
                        } else {
                            Write-Host "$data" -NoNewline
                        }
                    }
                }

                if ($WriteMode -and [Console]::KeyAvailable) {
                    if ($ShowDirection) { Write-Host ">> " -NoNewline }
                    $msg = [Console]::ReadLine()
                    if ($msg -ne $null -and $msg.Trim() -ne "") {
                        $sp.WriteLine($msg.Trim())
                        if ($NoExit) { Write-Host ">>" $msg.Trim() }
                    }
                }

                Start-Sleep -Milliseconds $RefreshRate
            }
        }
        catch {
            if ($AutoConnect) {
                Start-Sleep -Milliseconds $ConnectRate
                continue
            } else {
                Write-Warning "$_"
                break
            }
        }
        finally {
            if ($sp.IsOpen) {
                $sp.Close()
                Write-Host "`nClosed $Argument"
            }
        }
        if ($AutoConnect) {
            Start-Sleep -Milliseconds $ConnectRate
            continue
        }
        break
    }
}

Connect-Port
