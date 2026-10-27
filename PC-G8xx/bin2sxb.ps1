<#
bin2sxb.ps1 - make an .sxb file (for SXRECVB on the Sharp PC-G850V / G850 / G815) from a .bin.
Windows PowerShell 5.1 (built into Windows 7 and later) or PowerShell 7; nothing to install.
Normally started through bin2sxb.bat:

    bin2sxb prog.bin 1000                  -> prog.sxb, no start address
    bin2sxb prog.bin 1000 --exec 1000      -> the BASIC stub offers to run &H1000
    bin2sxb prog.bin 1000 --exec 1000 -o game.sxb

Addresses in hex (1000 or 0x1000).

SXB format (see the README):
  +0  'S' 'X'        marker
  +2  load address   low byte first
  +4  length n       low byte first, 1..65535
  +6  exec address   low byte first, 0xFFFF = none
  +8  header check   bytes +2..+8 add up to 0 (mod 256)
  +9  n data bytes
  then the CRC-16/XMODEM of the data (polynomial 0x1021, start 0), high byte first

Copyright (c) 2026 Radovan Hrebicek. MIT License (see LICENSE).
#>

function Fail([string]$msg) { [Console]::Error.WriteLine("bin2sxb: $msg"); exit 1 }

function Get-Hex([string]$s, [string]$what) {
    $t = $s.Trim()
    foreach ($p in @("&H", "&h", "0x", "0X", "$")) { if ($t.StartsWith($p)) { $t = $t.Substring($p.Length); break } }
    if ($t -notmatch '^[0-9A-Fa-f]{1,4}$') { Fail "$what '$s' is not a hex address 0..FFFF" }
    return [Convert]::ToInt32($t, 16)
}

# --- arguments: FILE.bin ADDR [--exec ADDR] [-o OUT.sxb] --------------------------
$pos = @(); $exec = $null; $out = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    if ($a -match '^--?exec$') { $i++; if ($i -ge $args.Count) { Fail "--exec needs an address" }; $exec = Get-Hex ([string]$args[$i]) "start address" }
    elseif ($a -match '^(-o|--out)$') { $i++; if ($i -ge $args.Count) { Fail "-o needs a file name" }; $out = [string]$args[$i] }
    else { $pos += $a }
}
if ($pos.Count -ne 2) {
    Write-Host "usage: bin2sxb FILE.bin ADDR [--exec ADDR] [-o OUT.sxb]   (addresses in hex, e.g. 1000)"
    exit 1
}
$binPath = $pos[0]
$la = Get-Hex $pos[1] "load address"
if (-not (Test-Path -LiteralPath $binPath -PathType Leaf)) { Fail "file not found: $binPath" }
$binFull = (Resolve-Path -LiteralPath $binPath).Path
$data = [System.IO.File]::ReadAllBytes($binFull)
$n = $data.Length
if ($n -lt 1 -or $n -gt 65535) { Fail "an .sxb holds 1..65535 bytes, $binPath has $n" }
if (($la + $n) -gt 65536) { Fail ("0x{0:X4} + {1} bytes runs past 0xFFFF" -f $la, $n) }
if (-not $out) { $out = [System.IO.Path]::ChangeExtension($binFull, ".sxb") }
elseif (-not [System.IO.Path]::IsPathRooted($out)) { $out = Join-Path (Get-Location).Path $out }

# --- header, CRC, file ----------------------------------------------------------------
$ex = if ($null -ne $exec) { $exec } else { 0xFFFF }
$hdr = [byte[]]@(($la -band 0xFF), (($la -shr 8) -band 0xFF), ($n -band 0xFF), (($n -shr 8) -band 0xFF),
                 ($ex -band 0xFF), (($ex -shr 8) -band 0xFF))
$hsum = 0; foreach ($x in $hdr) { $hsum += $x }
$crc = 0
foreach ($b in $data) {
    $crc = $crc -bxor ([int]$b -shl 8)
    for ($i = 0; $i -lt 8; $i++) {
        if ($crc -band 0x8000) { $crc = (($crc -shl 1) -bxor 0x1021) -band 0xFFFF }
        else                   { $crc = ($crc -shl 1) -band 0xFFFF }
    }
}
$sx = New-Object System.Collections.Generic.List[byte]
$sx.Add(0x53); $sx.Add(0x58)                        # "SX"
$sx.AddRange($hdr)
$sx.Add([byte]((256 - ($hsum % 256)) % 256))
$sx.AddRange($data)
$sx.Add([byte](($crc -shr 8) -band 0xFF)); $sx.Add([byte]($crc -band 0xFF))
[System.IO.File]::WriteAllBytes($out, $sx.ToArray())

$exText = if ($null -ne $exec) { "exec 0x{0:X4}" -f $exec } else { "no exec" }
Write-Host ("{0}: 0x{1:X4}-0x{2:X4} ({3} bytes), {4}, CRC 0x{5:X4}, {6} bytes to send" -f $out, $la, ($la + $n - 1), $n, $exText, $crc, $sx.Count)
exit 0
