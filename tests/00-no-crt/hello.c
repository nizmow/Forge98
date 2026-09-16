__declspec(dllimport) void __stdcall ExitProcess(unsigned int uExitCode);

void mainCRTStartup(void)
{
    ExitProcess(0);
}
