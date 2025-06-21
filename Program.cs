using System;
using System.CommandLine;
using System.CommandLine.Invocation;
using System.IO.Ports;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Management;

class Program
{
    static async Task<int> Main(string[] args)
    {
        var rootCommand = new RootCommand("wincom - lightweight serial terminal");

        var portArgument = new Argument<string?>("argument")
        {
            Description = "  COM[N]       e.g. COM3\nlist         Show available serial ports"
        };
        var baudOption = new Option<int>("--baud-rate", () => 115200, "Baud rate");
        var writeModeOption = new Option<bool>("--write-mode", "Enable read & write mode");
        var showDirectionOption = new Option<bool>("--show-direction", "Show << / >> for RX / TX");

        rootCommand.AddArgument(portArgument);
        rootCommand.AddOption(baudOption);
        rootCommand.AddOption(writeModeOption);
        rootCommand.AddOption(showDirectionOption);

        rootCommand.SetHandler(async (string? target, int baudRate, bool writeMode, bool showDirection) =>
        {
            if (string.IsNullOrEmpty(target))
            {
                Console.WriteLine("Missing argument.\n");
                rootCommand.Invoke("--help");
                return;
            }

            if (target.Equals("list", StringComparison.OrdinalIgnoreCase))
            {
                ListPorts();
                return;
            }

            if (!Regex.IsMatch(target, "^COM\\d+$", RegexOptions.IgnoreCase))
            {
                Console.Error.WriteLine("Invalid COM port.\n");
                rootCommand.Invoke("--help");
                return;
            }

            var cts = new CancellationTokenSource();
            Console.CancelKeyPress += (s, e) => {
                e.Cancel = true;
                cts.Cancel();
            };

            using (var sp = new SerialPort(target, baudRate, Parity.None, 8, StopBits.One))
            {
                sp.Encoding = Encoding.ASCII;
                sp.NewLine = "\n";
                sp.ReadTimeout = 200;

                try
                {
                    sp.Open();
                    Console.Write($"Opened {target} @ {baudRate} baud. ");
                    if (writeMode)
                        Console.WriteLine("WriteMode ON. Type and Enter to send. Ctrl+C to quit.\n");
                    else
                        Console.WriteLine("Read-only. Ctrl+C to quit.\n");

                    await RunLoop(sp, writeMode, showDirection, cts.Token);
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"Error: {ex.Message}");
                }
                finally
                {
                    if (sp.IsOpen)
                    {
                        sp.Close();
                        Console.WriteLine($"\nClosed {target}");
                    }
                }
            }

        }, portArgument, baudOption, writeModeOption, showDirectionOption);

        return await rootCommand.InvokeAsync(args);
    }

    static async Task RunLoop(SerialPort sp, bool writeMode, bool showDirection, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                if (sp.BytesToRead > 0)
                {
                    string data = sp.ReadExisting();
                    if (!string.IsNullOrEmpty(data))
                    {
                        if (showDirection)
                            Console.Write($"<< {data}");
                        else
                            Console.Write(data);
                    }
                }
            }
            catch (TimeoutException) { }

            if (writeMode && Console.KeyAvailable)
            {
                if (showDirection)
                    Console.Write(">> ");
                string? msg = Console.ReadLine();
                if (!string.IsNullOrWhiteSpace(msg))
                {
                    sp.WriteLine(msg.Trim());
                }
            }

            await Task.Delay(100, token);
        }
    }

    static void ListPorts()
    {
        try
        {
            using var searcher = new System.Management.ManagementObjectSearcher("SELECT * FROM Win32_SerialPort");
            foreach (var obj in searcher.Get())
            {
                var deviceId = obj["DeviceID"]?.ToString();
                var name = obj["Description"]?.ToString();
                if (!string.IsNullOrEmpty(deviceId))
                {
                    Console.WriteLine($"{deviceId,-8} {name}");
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("Failed to query serial ports: " + ex.Message);
            Console.WriteLine("Falling back to basic port listing:");
            foreach (var port in SerialPort.GetPortNames())
            {
                Console.WriteLine(port);
            }
        }
    }
}
