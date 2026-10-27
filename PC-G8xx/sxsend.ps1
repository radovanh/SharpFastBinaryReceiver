<#
.SYNOPSIS
sxsend - send a .sxb file to SXBIN over a serial port (no Python / pyserial needed).

.DESCRIPTION
    .\sxsend.ps1 COM5 prog.sxb [-Baud 9600] [-Stop 1|2] [-Pause MS] [-Delay MS] [-RtsCts]

Raw binary, 8N1, no XON/XOFF. PC-G850V: the defaults. PC-G815 (bit-banged receiver): use
-Stop 2, or -Pause 5 (silence after the header, where the receiver checks the address);
-Delay adds a pause after every byte.
Start it only when the pocket computer shows the waiting screen.
Same options as sxsend.py.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Port,
    [Parameter(Mandatory = $true, Position = 1)][string]$File,
    [int]$Baud = 9600,
    [ValidateSet(1, 2)][int]$Stop = 1,
    [int]$Delay = 0,
    [int]$Pause = 0,
    [switch]$RtsCts
)

$ErrorActionPreference = 'Stop'

$data = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $File).Path)
if ($data.Length -lt 2 -or $data[0] -ne 0x53 -or $data[1] -ne 0x58) {
    throw "$File is not an .sxb file (no 'SX' marker); make one with bin2sxb.ps1"
}

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, ([System.IO.Ports.Parity]::None), 8, $(if ($Stop -eq 2) { [System.IO.Ports.StopBits]::Two } else { [System.IO.Ports.StopBits]::One })
$sp.Handshake = if ($RtsCts) { [System.IO.Ports.Handshake]::RequestToSend } else { [System.IO.Ports.Handshake]::None }
$sp.WriteTimeout = 30000
$sp.Open()

function Wait-Drain { while ($sp.BytesToWrite -gt 0) { Start-Sleep -Milliseconds 1 } }

try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $total = $data.Length
    $off = 0
    if ($Pause -gt 0) {
        $sp.Write($data, 0, 9)
        Wait-Drain
        Start-Sleep -Milliseconds $Pause
        $off = 9
    }
    if ($Delay -gt 0) {
        for ($i = $off; $i -lt $total; $i++) {
            $sp.Write($data, $i, 1)
            Wait-Drain
            Start-Sleep -Milliseconds $Delay
        }
    }
    else {
        $sp.Write($data, $off, $total - $off)
    }
    Wait-Drain
    Start-Sleep -Milliseconds 200
    $sw.Stop()
}
finally {
    $sp.Close()
}
"sent {0} bytes in {1:N1} s ({2} baud, {3} stop bit(s))" -f $total, $sw.Elapsed.TotalSeconds, $Baud, $Stop
