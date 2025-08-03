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
if ($Argument -eq "list") {
    if (-not (Get-CimInstance Win32_SerialPort)) {
        Write-Warning "No COM ports found."
        return
    }
    Get-CimInstance Win32_SerialPort |
      Select-Object DeviceID, Description |
      Format-Table -AutoSize
    return
}
if (-not $Argument) {
    $Argument = (Get-CimInstance Win32_SerialPort | Select-Object -First 1 -ExpandProperty DeviceID)
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
