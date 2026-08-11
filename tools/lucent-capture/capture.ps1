<#
  capture.ps1 - capture one Synapse action off the Razer keyboard.

  Usage:
    .\capture.ps1 00-mode-silent
    .\capture.ps1 01-cpu-power-60

  Starts the capture, waits for you to perform the action in Synapse, then
  stops, converts to pcapng and prints what was captured.
#>
param(
  [Parameter(Mandatory=$true)][string]$Name
)

$usbpcap = "C:\Program Files\USBPcap\USBPcapCMD.exe"
$editcap = "C:\Program Files\Wireshark\editcap.exe"
$dir     = $PSScriptRoot
$raw     = Join-Path $dir "$Name.pcap"
$final   = Join-Path $dir "$Name.pcapng"

# USBPcap1 = the root hub holding the Razer composite device; --devices 1 is
# that device's address on it. Both verified on this machine.
$iface  = '\\.\USBPcap1'
$device = '1'

foreach ($f in @($raw, $final)) { if (Test-Path $f) { Remove-Item $f -Force } }

Write-Host ""
Write-Host "  capturing -> $Name.pcapng" -ForegroundColor Cyan

$proc = Start-Process -FilePath $usbpcap `
  -ArgumentList '-d', $iface, '-o', "`"$raw`"", '--devices', $device `
  -PassThru -WindowStyle Hidden

Start-Sleep -Milliseconds 600
if ($proc.HasExited) { throw "capture failed to start (exit $($proc.ExitCode))" }

Write-Host ""
Write-Host "  >> PERFORM THE ACTION IN SYNAPSE NOW <<" -ForegroundColor Yellow
Write-Host "     then come back here and press Enter" -ForegroundColor Yellow
Write-Host ""
[void](Read-Host "  press Enter when the action is applied")

if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
Start-Sleep -Milliseconds 800

if (-not (Test-Path $raw)) { throw "no capture file was produced" }

& $editcap $raw $final 2>$null
if (-not (Test-Path $final)) {
  Write-Host "  editcap failed; keeping raw pcap" -ForegroundColor Yellow
  $final = $raw
} else {
  Remove-Item $raw -Force
}

Write-Host "  saved $([Math]::Round((Get-Item $final).Length / 1KB, 1)) KB" -ForegroundColor Green

& (Join-Path $dir 'decode.ps1') -Path $final
