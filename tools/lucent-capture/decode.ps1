<#
  decode.ps1 - summarise Razer 90-byte HID feature reports in a capture.

  Usage:
    .\decode.ps1 -Path 00-mode-silent.pcapng
    .\decode.ps1 -Path 01-cpu-power-60.pcapng -All      # include RGB noise
#>
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [switch]$All,          # do not hide the class 0x03 lighting stream
  [int]$ArgBytes = 16    # how many argument bytes to print
)

$tshark = "C:\Program Files\Wireshark\tshark.exe"
if (-not (Test-Path $tshark)) { throw "tshark not found at $tshark" }
if (-not (Test-Path $Path))   { throw "capture not found: $Path" }

# usb.data_fragment holds the full 90-byte report for SET_REPORT control transfers.
$rows = & $tshark -r $Path -Y "usb.data_fragment" -T fields -e frame.number -e usb.data_fragment 2>$null

$reports = @()
foreach ($row in $rows) {
  $parts = $row -split "`t"
  if ($parts.Count -lt 2) { continue }
  $hex = ($parts[1] -replace '[^0-9a-fA-F]','')
  if ($hex.Length -lt 18) { continue }

  # 90-byte report layout (see WINDOWS-CAPTURE.md):
  #   0 status | 1 txn | 2-3 remaining | 4 proto | 5 size | 6 class | 7 id | 8.. args
  $b = @()
  for ($i = 0; $i -lt $hex.Length; $i += 2) { $b += [Convert]::ToByte($hex.Substring($i,2),16) }

  $reports += [PSCustomObject]@{
    Frame = [int]$parts[0]
    Status= $b[0]
    Txn   = $b[1]
    Size  = $b[5]
    Class = $b[6]
    Id    = $b[7]
    Args  = $b[8..([Math]::Min(7 + $ArgBytes, $b.Length - 1))]
  }
}

if (-not $All) { $shown = $reports | Where-Object { $_.Class -ne 0x03 } }
else           { $shown = $reports }

Write-Host ""
Write-Host "$Path" -ForegroundColor Cyan
Write-Host ("  {0} report(s) total, {1} lighting (class 0x03), {2} shown" -f `
  $reports.Count, ($reports | Where-Object { $_.Class -eq 0x03 }).Count, $shown.Count)
Write-Host ""

if (-not $shown -or $shown.Count -eq 0) {
  Write-Host "  no non-lighting commands captured" -ForegroundColor Yellow
  Write-Host "  -> the action may have landed outside the capture window; try again" -ForegroundColor Yellow
  Write-Host ""
  return
}

"{0,-7} {1,-6} {2,-6} {3,-6} {4}" -f 'frame','class','id','size','args'
"{0,-7} {1,-6} {2,-6} {3,-6} {4}" -f '-----','-----','----','----','----'
foreach ($r in $shown) {
  $argHex = ($r.Args | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
  "{0,-7} 0x{1:x2}   0x{2:x2}   {3,-6} {4}" -f $r.Frame, $r.Class, $r.Id, $r.Size, $argHex
}
Write-Host ""

# Highlight the class 0x0d hits, which is what this whole exercise is hunting.
$hits = $shown | Where-Object { $_.Class -eq 0x0d }
if ($hits) {
  Write-Host "  class 0x0d command ids seen: " -NoNewline -ForegroundColor Green
  Write-Host ((($hits | ForEach-Object { '0x{0:x2}' -f $_.Id }) | Sort-Object -Unique) -join ', ') -ForegroundColor Green
  Write-Host ""
}
