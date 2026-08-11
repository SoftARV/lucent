<#
  decode-replies.ps1 - decode the EC's *replies*, which decode.ps1 does not show.

  A command is four USB frames; the reply is the fourth. It has no
  bmRequestType and no usb.data_fragment field, so the request-side filters miss
  it entirely. The 90 bytes sit raw after the USBPcap pseudoheader, whose length
  is the first two bytes of the frame (little endian).

  Usage:
    .\decode-replies.ps1 -Path 40-synapse-start.pcapng
    .\decode-replies.ps1 -Path 40-synapse-start.pcapng -Unique
#>
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [switch]$Unique,       # one line per distinct class/id instead of every frame
  [int]$ArgBytes = 16
)

$tshark = "C:\Program Files\Wireshark\tshark.exe"
if (-not (Test-Path $tshark)) { throw "tshark not found at $tshark" }
if (-not (Test-Path $Path))   { throw "capture not found: $Path" }

$json = & $tshark -r $Path -Y "usb.data_len == 90" -T json -x 2>$null | Out-String
if (-not $json.Trim()) { Write-Host "no reply frames in $Path"; return }
$pkts = $json | ConvertFrom-Json

$rows = @()
foreach ($pk in $pkts) {
  $raw = $pk._source.layers.frame_raw
  if (-not $raw) { continue }
  $hex = if ($raw -is [array]) { $raw[0] } else { $raw }

  # USBPcap pseudoheader length is the first uint16, little endian.
  $hdr = [Convert]::ToInt32($hex.Substring(2,2) + $hex.Substring(0,2), 16)
  $pl  = $hex.Substring($hdr * 2)
  if ($pl.Length -lt 40) { continue }

  $cls = $pl.Substring(12,2)
  if ($cls -eq '03') { continue }   # RGB lighting noise
  $size = [Convert]::ToInt32($pl.Substring(10,2), 16)
  $n = [Math]::Min($size, $ArgBytes)

  $rows += [PSCustomObject]@{
    Status = $pl.Substring(0,2)
    Class  = $cls
    Id     = $pl.Substring(14,2)
    Size   = $size
    Args   = (($pl.Substring(16, $n*2) -split '(..)' | Where-Object { $_ }) -join ' ')
  }
}

Write-Host ""
Write-Host "$Path" -ForegroundColor Cyan
Write-Host "  $($rows.Count) reply frame(s), lighting excluded"
Write-Host ""

if ($Unique) { $rows = $rows | Sort-Object Class, Id, Args -Unique }

"{0,-8} {1,-7} {2,-6} {3,-6} {4}" -f 'status','class','id','size','args'
"{0,-8} {1,-7} {2,-6} {3,-6} {4}" -f '------','-----','----','----','----'
foreach ($r in $rows) {
  $ok = if ($r.Status -eq '02') { 'ok' } else { "0x$($r.Status)" }
  "{0,-8} 0x{1,-5} 0x{2,-4} {3,-6} {4}" -f $ok, $r.Class, $r.Id, $r.Size, $r.Args
}
Write-Host ""
