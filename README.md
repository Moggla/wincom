# wincom

**wincom** is a lightweight command-line tool for serial communication on Windows.

## Requirements

### [PS2EXE](https://github.com/MScholtes/PS2EXE)
```powershell
Install-Module ps2exe
```

### [winget-create](https://github.com/microsoft/winget-create)
```powershell
winget install wingetcreate
```

## Run

```powershell
git clone https://github.com/Moggla/wincom
cd wincom
.\wincom.ps1
```

## Compile as Executable

```powershell
ps2exe .\wincom.ps1 .\wincom.exe -version '0.0.1'
```

## Update Windows Package Manager Manifest

```powershell
wingetcreate update Moggla.wincom --urls 'https://github.com/Moggla/wincom/releases/download/v0.0.1/wincom.exe|x64' 'https://github.com/Moggla/wincom/releases/download/v0.0.1/wincom.exe|x86' --version '0.0.1'
```

Test new manifest:
```powershell
winget validate --manifest .\manifests\m\Moggla\wincom\0.0.1\
winget install --manifest .\manifests\m\Moggla\wincom\0.0.1\
```
