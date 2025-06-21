# wincom

**wincom** is a lightweight command-line tool for serial communication on Windows.

## Requirements

* [.NET SDK](https://dotnet.microsoft.com/download)

## Build and Run

```bash
git clone https://github.com/your-username/wincom.git
cd wincom
dotnet build
dotnet run -- [arguments]
```

## Publish as Executable

To publish as a single `.exe` file:

```bash
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true -o publish
```

The executable will be in:

```
bin/Release/net8.0-windows/win-x64/publish/wincom.exe
```
