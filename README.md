# wincom

**wincom** is a lightweight command-line tool for serial communication on Windows.
No installer, no runtime: a single executable that works in any terminal.

## Install

```powershell
winget install Moggla.wincom
```

## Usage

```powershell
wincom list                              # show available ports with description and VID:PID
wincom COM3                              # read-only at 115200 baud
wincom COM3 -BaudRate 9600 -WriteMode    # read and write
wincom -Match CP210 -AutoConnect         # pick the port by name, reconnect after unplugging
wincom COM3 -WriteMode -LineEnding CRLF  # e.g. for AT commands
wincom COM3 -Timestamp -LogFile log.txt  # timestamped output, also written to a file
wincom COM3 -Hex -WriteMode              # show and send raw bytes as hex
```

Without a port argument, wincom opens the first available port.

### Options

| Option | Description |
| --- | --- |
| `-Match <regex>` | Use the first port whose name, description or VID:PID matches, e.g. `CP210` or `303A:1001` (also filters `list`) |
| `-WriteMode` | Enable read & write mode |
| `-NoEcho` | Do not print sent input (for devices that echo it back) |
| `-SendFile <path>` | Send the file's raw bytes once after the port is opened |
| `-ShowDirection` | Show `<<` / `>>` for RX / TX |
| `-Timestamp` | Show a timestamp in front of each line |
| `-LogFile <path>` | Append the session output to a file |
| `-Hex` | Show received bytes as hex, send input as hex bytes (`48 65 6C`, `48656C` or `0x48,0x65`) |
| `-NoColor` | Disable colors (also set by the `NO_COLOR` environment variable) |
| `-NoExit` | Do not quit on Ctrl+C (sent to the device in write mode) |
| `-AutoConnect` | Wait for the port and reconnect after it disappears |
| `-ConnectRate <int>` | AutoConnect rate in milliseconds (default `2000`) |
| `-RefreshRate <int>` | Refresh rate in milliseconds (default `20`) |
| `-BaudRate <int>` | Baud rate (default `115200`) |
| `-Parity <string>` | `None`, `Odd`, `Even`, `Mark` or `Space` (default `None`) |
| `-DataBits <int>` | `5` to `8` (default `8`) |
| `-StopBits <string>` | `One`, `OnePointFive` or `Two` (default `One`) |
| `-LineEnding <string>` | `LF`, `CR`, `CRLF` or `None` appended when sending (default `LF`) |
| `-Encoding <string>` | `UTF8`, `ASCII` or `Latin1` (default `UTF8`) |
| `-Dtr` | Enable DTR |
| `-Rts` | Enable RTS |
| `-Version` | Show version information |
| `-Help` | Show help and usage information |

### Keys

| Key | Action |
| --- | --- |
| `Ctrl+Q` | Quit |
| `Ctrl+C` | Quit (sent to the device with `-NoExit -WriteMode`, e.g. to interrupt a MicroPython REPL) |
| `Enter` / `Esc` | Send / clear the current input |
| `Up` / `Down` | Browse previously sent input |

### Troubleshooting

- **The port opens but nothing arrives:** many USB CDC devices (Arduino Leonardo, RP2040, ESP32-S3 native USB, ...) only send while DTR is set. Try `-Dtr`.
- **The device ignores commands:** it probably expects a different line ending, try `-LineEnding CRLF` or `-LineEnding CR`.
- **Every sent line appears twice:** the device echoes input itself, use `-NoEcho`.
- **The COM number keeps changing:** select the device with `-Match` instead, e.g. its VID:PID from `wincom list`.

## Development

### Requirements

- [PS2EXE](https://github.com/MScholtes/PS2EXE) to compile the executable:
  ```powershell
  Install-Module ps2exe
  ```
- [winget-create](https://github.com/microsoft/winget-create) (optional, for manual manifest updates):
  ```powershell
  winget install wingetcreate
  ```

### Run from source

```powershell
git clone https://github.com/Moggla/wincom
cd wincom
.\wincom.ps1 list
```

### Compile as executable

```powershell
.\build.ps1 -Version 0.0.1
```

The version is stamped into the executable; when run from source, `-Version` reports `dev`.

### Release

Publishing a GitHub release with a tag like `v0.0.2` runs the [workflow](.github/workflows/winget.yml), which builds `wincom.exe`, attaches it to the release and submits the update to winget.
It needs a `WINGET_TOKEN` repository secret: a GitHub personal access token with `public_repo` scope, which wingetcreate uses to open the pull request in [winget-pkgs](https://github.com/microsoft/winget-pkgs).

### Manually update the Windows Package Manager manifest

```powershell
wingetcreate update Moggla.wincom --urls 'https://github.com/Moggla/wincom/releases/download/v0.0.1/wincom.exe|x64' 'https://github.com/Moggla/wincom/releases/download/v0.0.1/wincom.exe|x86' --version '0.0.1'
```

Test manifest:
```powershell
winget validate --manifest .\manifests\m\Moggla\wincom\0.0.1\
winget install --manifest .\manifests\m\Moggla\wincom\0.0.1\
```
