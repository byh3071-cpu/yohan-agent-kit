# CF_HTML을 UTF-8 바이트 오프셋으로 직접 빌드해 클립보드에 넣는다.
# PS 5.1 Set-Clipboard -AsHtml의 ANSI 인코딩 버그 우회.
param([Parameter(Mandatory=$true)][string]$Path)

# 에이전트가 결과 줄을 읽을 때 한국어가 깨지지 않게, 파이프로 넘길 때만 UTF-8 로 낸다(PAT-002).
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) }

Add-Type -AssemblyName System.Windows.Forms

$rawHtml = Get-Content -Raw -Encoding UTF8 $Path
$enc = [System.Text.Encoding]::UTF8

$pre  = "<html><body><!--StartFragment-->"
$post = "<!--EndFragment--></body></html>"

$headerTemplate = "Version:0.9`r`nStartHTML:0000000000`r`nEndHTML:0000000000`r`nStartFragment:0000000000`r`nEndFragment:0000000000`r`n"
$headerLen = $enc.GetByteCount($headerTemplate)
$preLen  = $enc.GetByteCount($pre)
$htmlLen = $enc.GetByteCount($rawHtml)
$postLen = $enc.GetByteCount($post)

$startHtml = $headerLen
$endHtml   = $headerLen + $preLen + $htmlLen + $postLen
$startFrag = $headerLen + $preLen
$endFrag   = $headerLen + $preLen + $htmlLen

$header = "Version:0.9`r`nStartHTML:$($startHtml.ToString('D10'))`r`nEndHTML:$($endHtml.ToString('D10'))`r`nStartFragment:$($startFrag.ToString('D10'))`r`nEndFragment:$($endFrag.ToString('D10'))`r`n"
$payload = $header + $pre + $rawHtml + $post
$bytes = $enc.GetBytes($payload)
$ms = New-Object System.IO.MemoryStream(,$bytes)

$do = New-Object System.Windows.Forms.DataObject
$do.SetData("HTML Format", $ms)
# 평문 폴백도 같이 (서식 안 받는 앱용)
$plain = $rawHtml -replace '<[^>]+>',''
$do.SetData([System.Windows.Forms.DataFormats]::UnicodeText, $plain)
[System.Windows.Forms.Clipboard]::SetDataObject($do, $true)

"CF_HTML UTF-8 클립보드 완료: HTML $htmlLen bytes"
