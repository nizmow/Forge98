' FORGE98 guest harness.
' Runs the test binary from the input volume and reports over COM1.
' Uses only Windows Script Host and command.com, both shipped with Windows 98 SE.

Option Explicit

Dim fso, shell, base, i, letter, stdoutFlag, exePath, rc, cmd

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

base = FindShare()
If base = "" Then
    Emit "@@FORGE98:BEGIN"
    Emit "@@FORGE98:ERROR=share not found"
    Emit "@@FORGE98:END"
    WScript.Quit 2
End If

stdoutFlag = ReadIni(base & "\TEST.INI", "Stdout", "1")
exePath = base & "\TEST.EXE"

Emit "@@FORGE98:BEGIN"
Emit "@@FORGE98:TEST=" & fso.GetFileName(exePath)

If Not fso.FileExists(exePath) Then
    Emit "@@FORGE98:ERROR=TEST.EXE not found"
    Emit "@@FORGE98:END"
    WScript.Quit 3
End If

Emit "--- STDOUT ---"
If stdoutFlag = "1" Then
    cmd = "command.com /c """ & exePath & """ > COM1"
    rc = shell.Run(cmd, 0, True)
Else
    rc = shell.Run("""" & exePath & """", 1, True)
End If
Emit "--- END STDOUT ---"
Emit "@@FORGE98:EXITCODE=" & rc
Emit "@@FORGE98:END"

Function FindShare()
    FindShare = ""
    For i = Asc("D") To Asc("Z")
        letter = Chr(i) & ":"
        If fso.FileExists(letter & "\FORGE98\FORGE98.MARK") Then
            FindShare = letter & "\FORGE98"
            Exit Function
        End If
    Next
End Function

Function ReadIni(path, key, def)
    Dim ts, line, parts
    ReadIni = def
    If Not fso.FileExists(path) Then Exit Function
    Set ts = fso.OpenTextFile(path, 1)
    Do While Not ts.AtEndOfStream
        line = ts.ReadLine
        parts = Split(line, "=")
        If UBound(parts) >= 1 Then
            If LCase(Trim(parts(0))) = LCase(key) Then
                ReadIni = Trim(parts(1))
            End If
        End If
    Loop
    ts.Close
End Function

Sub Emit(text)
    shell.Run "command.com /c echo " & text & ">COM1", 0, True
End Sub
