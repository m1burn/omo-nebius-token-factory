// VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
// - S4487 / Roslynator RCS1213: private const NeverRead is declared but never used
// - S2068: hardcoded password constant (fake placeholder value, scanners only)
namespace QualitySmoke;

public static class Program
{
    private const int NeverRead = 128;

    private const string DefaultPassword = "NotARealP@ssw0rd-ScanMe-0000";

    public static void Main()
    {
        System.Console.WriteLine("quality smoke build vehicle");
    }
}
