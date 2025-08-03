# wincom

**wincom** is a lightweight command-line tool for serial communication on Windows.

## Requirements

### [PS2EXE](https://github.com/MScholtes/PS2EXE)
```powershell
Install-Module ps2exe
```

## Run

```powershell
git clone https://github.com/Moggla/wincom
cd wincom
.\wincom.ps1
```

## Compile as Executable

To convert the powershell script into an `.exe` file:

```powershell
ps2exe .\wincom.ps1 .\wincom.exe -version '0.0.1'
```
