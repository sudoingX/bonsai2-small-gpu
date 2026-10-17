# Bonsai 2 27B on Windows: start the model, or check its speed.
#   start-bonsai.bat  runs  bonsai2.ps1 start   the chat page at http://127.0.0.1:8899
#   bench-bonsai.bat  runs  bonsai2.ps1 bench   a results block, saved next to this file and copied to the clipboard
#   bonsai2.ps1 print                           shows the server command lines and changes nothing
# install.ps1 from github.com/sudoingX/local-ai-on-your-gaming-gpu puts this file here, with its settings in bonsai2.json.
param([string]$Mode = 'start')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$inv  = [Globalization.CultureInfo]::InvariantCulture
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg  = Get-Content (Join-Path $here 'bonsai2.json') -Raw | ConvertFrom-Json
# the build's own names: an Offrail install says Offrail 27B and answers to offrail-27b. A bonsai2.json
# written by an older installer has neither field, so both fall back to the standard build.
$vname = if ($cfg.name)  { "$($cfg.name)" }  else { 'Bonsai 2 27B' }
$alias = if ($cfg.alias) { "$($cfg.alias)" } else { 'bonsai-2-27b' }
$slug  = if ($cfg.slug)  { "$($cfg.slug)" }  else { 'bonsai2' }
$exe  = Join-Path $here "$($cfg.build)\bin\llama-server.exe"
$smi  = "$env:SystemRoot\System32\nvidia-smi.exe"
if (-not (Test-Path $smi)) { $c = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue; if ($c) { $smi = $c.Source } }
# AMD Radeon (beta): PrismML's Vulkan build, its files sit in the build folder itself, and there is no nvidia-smi
$vulkan = $cfg.backend -eq 'vulkan'
# RTX 20 (Turing, compute 7.5): its own 8 GB window steps and ubatch 256
$turing = (-not $vulkan) -and $cfg.cc -and ([double]::Parse("$($cfg.cc)", $inv) -lt 8.0)

if ($vulkan) {
    $exe = Join-Path $here "$($cfg.build)\llama-server.exe"
} else {
    $env:CUDA_DEVICE_ORDER = 'PCI_BUS_ID'
    $env:CUDA_VISIBLE_DEVICES = "$($cfg.gpuIndex)"
    $env:GGML_CUDA_BATCH_INVARIANT = '1'
}

# AMD: the Vulkan device of this Radeon, found by its memory (an APU: the biggest one) so the model never lands on an
# integrated GPU, with the free memory Vulkan reports for it. CI: BONSAI_FAKE_VK = the --list-devices lines, ';' between.
function Get-VkDevice {
    if ($env:BONSAI_FAKE_VK) { $lines = @($env:BONSAI_FAKE_VK -split ';') }
    else {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $lines = @(& $exe --list-devices 2>$null | ForEach-Object { "$_" })
        $ErrorActionPreference = $old
    }
    $best = $null
    foreach ($l in $lines) {
        if ($l -notmatch '^\s*(Vulkan\d+):\s*(.*)\((\d+) MiB, (\d+) MiB free\)\s*$') { continue }
        $name = $Matches[1]; $desc = $Matches[2].Trim(); $total = [int]$Matches[3]; $free = [int]$Matches[4]
        $d = [pscustomobject]@{ Name = $name; Desc = $desc; Total = $total; Free = $free; Amd = [int]($desc -match 'AMD|Radeon')
                                Score = $(if ($cfg.apu) { -$total } else { [math]::Abs($total - [int]$cfg.gpuMiB) }) }
        if (-not $best -or $d.Amd -gt $best.Amd -or ($d.Amd -eq $best.Amd -and $d.Score -lt $best.Score)) { $best = $d }
    }
    return $best
}
$script:vk = $null
function Get-Vk {
    if (-not $script:vk) {
        $script:vk = Get-VkDevice
        if (-not $script:vk) { throw 'No Vulkan device found. Update the AMD Adrenalin driver (it brings Vulkan), then try again.' }
    }
    return $script:vk
}

# AMD: dedicated memory in use per GPU from the GPU Adapter Memory counters (no nvidia-smi on a Radeon); the bench takes the
# adapter that grows the most when the model loads. No counters: n/a.
function Get-AdapterUse {
    $h = @{}
    try {
        foreach ($i in @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop)) {
            $h["$($i.Name)"] = [int]([double]$i.DedicatedUsage / 1MB)
        }
    } catch { }
    return $h
}

function Get-VramMiB([string]$field) {
    if ($env:BONSAI_FAKE_FREE -and $field -eq 'memory.free') { return [int]$env:BONSAI_FAKE_FREE }
    $v = & $smi "--query-gpu=$field" --format=csv,noheader,nounits -i "$($cfg.gpuIndex)"
    return [int]("$(@($v)[0])".Trim())
}

# Radeon 8 GB on Vulkan, the lean file with the head (n-max 2) and ubatch 256. Each step: the window, the MiB the card must
# have free and whether the draft model's cache goes q4_0. The MiB = the card's share of the server at the peak of a long
# prompt, measured on a Radeon 8060S with the host buffers left out (a discrete card keeps them in system RAM), plus 50 MiB.
# The q4_0 draft cache saves 80 to 280 MiB for about 3% decode, so it comes on only when it buys the bigger window.
function Get-Window8gbVulkan {
    $free = (Get-Vk).Free
    foreach ($s in @(@(65536, 8007, $false), @(65536, 7727, $true), @(49152, 7546, $false), @(49152, 7403, $true),
                     @(32768, 7178, $false), @(32768, 7098, $true))) {
        if ($free -ge $s[1]) { return @{ Ctx = $s[0]; Q4 = $s[2] } }
    }
    return @{ Ctx = 16384; Q4 = $true }
}

# 8 GB cards: --fit is too careful with the lean file (it stops at 16K), so pick the window from free VRAM.
# The lean file with the head uses about 7,150 MiB at 16K and 7,900 MiB at 64K (sweeps/rtx3000Ada-8gb.md).
function Get-Context8gb {
    if ($vulkan) { return (Get-Window8gbVulkan).Ctx }
    $free = Get-VramMiB 'memory.free'
    # RTX 20 (Turing), the lean file with the head at n-max 1 and ubatch 256: the server peaks at 6,720 MiB at 16K, 7,155 at 32K
    # and 7,587 at 48K after a 12,842-token prompt on an RTX 2070 Super (Linux); 64K does not load on 8 GB. Step = peak + 50.
    if ($turing) {
        if ($free -ge 7650) { return 49152 }
        if ($free -ge 7250) { return 32768 }
        return 16384
    }
    if ($free -ge 7950) { return 65536 }
    if ($free -ge 7700) { return 49152 }
    if ($free -ge 7450) { return 32768 }
    return 16384
}

# start mode serves on 127.0.0.1 unless BONSAI_HOST says otherwise (0.0.0.0 = your network, set BONSAI_API_KEY with it)
function Get-ServerArgs([int]$port, [bool]$head, [bool]$chat) {
    $bindHost = if ($chat -and $env:BONSAI_HOST) { $env:BONSAI_HOST } else { '127.0.0.1' }
    $a = @('-m', (Join-Path $here "models\$($cfg.model)"), '-ngl', '99', '-fa', 'on', '-np', '1', '-ctk', 'q4_0', '-ctv', 'q4_0', '--jinja',
           '--alias', $alias, '--host', $bindHost, '--port', "$port")
    if ($chat -and $env:BONSAI_API_KEY) { $a += @('--api-key', $env:BONSAI_API_KEY) }
    if ($cfg.mmproj) { $a += @('--mmproj', (Join-Path $here "models\$($cfg.mmproj)")) }
    if ($vulkan) { $a += @('--device', (Get-Vk).Name) }
    if ($cfg.tier -eq '8gb') { $a += @('-c', "$(Get-Context8gb)", '--fit', 'off') }
    else { $a += @('--fit', 'on', '--fit-target', '1024', '--fit-ctx', '16384') }
    # Radeon 8 and 12 GB: ubatch 256 (less memory, same decode); 12 GB always and 8 GB when its step says so: the draft
    # model's cache in q4_0 (12 GB: --fit picks about 195K instead of 158K for about 1% decode)
    if ($vulkan -and $cfg.tier -in @('8gb', '12gb')) { $a += @('-ub', '256') }
    if ($turing -and $cfg.tier -eq '8gb') { $a += @('-ub', '256') }
    if ($head) {
        $a += @('--spec-type', 'draft-mtp', '--spec-draft-n-max', "$($cfg.nmax)")
        if ($vulkan -and ($cfg.tier -eq '12gb' -or ($cfg.tier -eq '8gb' -and (Get-Window8gbVulkan).Q4))) { $a += @('-ctkd', 'q4_0', '-ctvd', 'q4_0') }
    }
    if ($chat) { $a += @('--reasoning-effort', 'medium', '--temp', '1.0', '--top-p', '0.95', '--top-k', '20') }
    return ,$a
}

function Join-Args($a) {
    ($a | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
}

$port = [int]$cfg.port
if ($env:BONSAI_PORT) { $port = [int]$env:BONSAI_PORT }

if ($Mode -eq 'print') {
    Write-Host ('start: "{0}" {1}' -f $exe, (Join-Args (Get-ServerArgs $port $true $true)))
    Write-Host ('bench: "{0}" {1}' -f $exe, (Join-Args (Get-ServerArgs 8091 $true $false)))
    return
}

if ($Mode -eq 'start') {
    if (Get-Process llama-server -ErrorAction SilentlyContinue) {
        Write-Host 'Bonsai is already running, opening the chat page.'
        Start-Process "http://127.0.0.1:$port"
        return
    }
    if ($vulkan) { $d = Get-Vk; Write-Host ('Radeon:          {0}, {1}, {2} MiB free (AMD Radeon beta, Vulkan)' -f $d.Name, $d.Desc, $d.Free) }
    Write-Host ('{0} is loading, the chat page opens in your browser when it is ready.' -f $vname) -ForegroundColor Cyan
    Write-Host "Chat page:       http://127.0.0.1:$port"
    Write-Host "API for agents:  http://127.0.0.1:$port/v1  (OpenAI compatible, model $alias, any API key unless you set BONSAI_API_KEY)"
    Write-Host 'Close this window to stop it.'
    Write-Host ''
    $poll = {
        param($p)
        for ($i = 0; $i -lt 900; $i++) {
            try {
                $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$p/health"
                Start-Process "http://127.0.0.1:$p"
                break
            } catch { Start-Sleep 1 }
        }
    }
    # open the chat page in the browser once the server is up: a background runspace in this same process,
    # not a hidden powershell child (Windows Defender flags hidden child shells as Trojan:Win32/Commando.A!ml)
    $null = [powershell]::Create().AddScript($poll).AddArgument($port).BeginInvoke()
    $ErrorActionPreference = 'Continue'
    $a = Get-ServerArgs $port $true $true
    & $exe @a
    return
}

if ($Mode -ne 'bench') { Write-Host "Unknown mode $Mode, use start, bench or print."; return }

# ---- bench: the same checks as the Linux sweeps, head on then head off ----
if (Get-Process llama-server -ErrorAction SilentlyContinue) {
    Write-Host 'Bonsai is already running, close its window first, then run the speed check again.' -ForegroundColor Red
    return
}
$bport = 8091
$base = "http://127.0.0.1:$bport"
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host ('{0} speed check, about 3 to 5 minutes. Close games and video apps first.' -f $vname) -ForegroundColor Cyan

function Start-Server([bool]$head) {
    $tag = if ($head) { 'head' } else { 'nohead' }
    $log = Join-Path $here "bench-server-$tag.log"
    $p = Start-Process -FilePath $exe -ArgumentList (Join-Args (Get-ServerArgs $bport $head $false)) -NoNewWindow -PassThru `
        -RedirectStandardError $log -RedirectStandardOutput "$log.out"
    for ($i = 0; $i -lt 900; $i++) {
        if ($p.HasExited) { throw "the server stopped while loading, the reason is at the end of $log" }
        try { $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "$base/health"; return $p } catch { Start-Sleep 1 }
    }
    throw "the server did not come up in 15 minutes, see $log"
}
function Stop-Server($p) {
    if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force; $null = $p.WaitForExit(30000) }
    Start-Sleep 2
}
function Ask([object[]]$messages, [int]$max) {
    $body = @{ messages = $messages; max_tokens = $max; temperature = 0; top_k = 1; seed = 42; chat_template_kwargs = @{ enable_thinking = $false } } | ConvertTo-Json -Depth 12
    $r = Invoke-RestMethod -Method Post -Uri "$base/v1/chat/completions" -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 1800
    [pscustomobject]@{ Text = [string]$r.choices[0].message.content; TokS = [double]$r.timings.predicted_per_second
                       DraftN = [int]$r.timings.draft_n; DraftOk = [int]$r.timings.draft_n_accepted }
}
function Get-Median([double[]]$x) {
    $s = @($x | Sort-Object); $n = $s.Count
    if ($n % 2) { return $s[[int][math]::Floor($n / 2)] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}
function Format-TokS([double]$v) { $v.ToString('0.0', $inv) }

$identity = 'Explain in about 150 words why speculative decoding with a multi-token prediction head can be lossless under greedy decoding.'
$speed = 'Write a detailed explanation of how a GPU runs a matrix-vector multiply: memory bandwidth, warps, caching and why decode is bandwidth bound.'
$img = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $here 'vision_check.png')))
$visionMsg = @(@{ role = 'user'; content = @(
    @{ type = 'image_url'; image_url = @{ url = "data:image/png;base64,$img" } },
    @{ type = 'text'; text = "This chart has a group called 'fresh chat' with three bars. Give the three tok/s values as JSON with keys stock, kernel, kernel_plus_head. Only the JSON." }) })

if ($vulkan) { $null = Get-Vk; $before = Get-AdapterUse } else { $before = Get-VramMiB 'memory.used' }
$res = @{}
$p = $null
try {
    foreach ($head in @($true, $false)) {
        $tag = if ($head) { 'on' } else { 'off' }
        Write-Host "Loading with the speed head $tag..."
        $p = Start-Server $head
        $ctx = (Invoke-RestMethod "$base/props").default_generation_settings.n_ctx
        $loaded = if ($vulkan) { Get-AdapterUse } else { Get-VramMiB 'memory.used' }
        Write-Host '  identity run'
        $id = Ask @(@{ role = 'user'; content = $identity }) 400
        $runs = @()
        foreach ($k in 1..3) { Write-Host "  speed run $k of 3"; $runs += Ask @(@{ role = 'user'; content = $speed }) 512 }
        $vis = $null
        if ($head -and $cfg.mmproj) { Write-Host '  vision check'; $vis = Ask $visionMsg 200 }
        $after = if ($vulkan) { Get-AdapterUse } else { Get-VramMiB 'memory.used' }
        $res[$tag] = @{ ctx = $ctx; loaded = $loaded; after = $after; id = $id; runs = $runs; vis = $vis }
        Stop-Server $p
        $p = $null
    }
} finally {
    if ($p) { Stop-Server $p }
}

$on = $res['on']; $off = $res['off']
if ($vulkan) {
    # the Radeon is the adapter whose dedicated memory grew the most when the model loaded with the head
    $key = $null; $grow = 0
    foreach ($k in @($on.loaded.Keys)) { if ($before.ContainsKey($k) -and ($on.loaded[$k] - $before[$k]) -gt $grow) { $grow = $on.loaded[$k] - $before[$k]; $key = $k } }
    if ($key) { $before = $before[$key]; foreach ($r in @($on, $off)) { $r.loaded = $r.loaded[$key]; $r.after = $r.after[$key] } }
    else { $before = 'n/a'; foreach ($r in @($on, $off)) { $r.loaded = 'n/a'; $r.after = 'n/a' } }
}
$onT = @($on.runs | ForEach-Object { $_.TokS }); $offT = @($off.runs | ForEach-Object { $_.TokS })
$mOn = Get-Median $onT; $mOff = Get-Median $offT
$gain = [math]::Round(($mOn / $mOff - 1) * 100)
$sign = if ($gain -ge 0) { '+' } else { '' }
$dn = ($on.runs | Measure-Object -Property DraftN -Sum).Sum
$da = ($on.runs | Measure-Object -Property DraftOk -Sum).Sum
$same = if ($on.id.Text -ceq $off.id.Text) { 'yes' } else { 'NO' }
$os = Get-CimInstance Win32_OperatingSystem
$cpu = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim()
$ram = [math]::Round($os.TotalVisibleMemorySize / 1MB)
$visionNote = if ($cfg.mmproj) { ' + vision' } else { '' }
$lines = @(
    "$vname, Windows speed check ($stamp, $($cfg.release))",
    "card: $($cfg.gpuName), $($cfg.gpuMiB) MiB, driver $($cfg.driver)",
    "system: $("$($os.Caption)".Trim()) $($os.Version), $cpu, $ram GB RAM",
    "build: $($cfg.build), tier $($cfg.tier), file $($cfg.model)$visionNote",
    "vram in use before start (desktop and other apps): $before MiB",
    "context: $($on.ctx) with the head, $($off.ctx) without",
    "vram with the head: $($on.loaded) MiB loaded, $($on.after) MiB after the runs",
    "speed with the head (mtp n-max $($cfg.nmax)): $(($onT | ForEach-Object { Format-TokS $_ }) -join ' / ') tok/s, median $(Format-TokS $mOn) tok/s, draft $da/$dn accepted",
    "speed without the head: $(($offT | ForEach-Object { Format-TokS $_ }) -join ' / ') tok/s, median $(Format-TokS $mOff) tok/s",
    "head gain: $sign$gain%",
    "same greedy text with and without the head: $same"
)
if ($on.vis) {
    $vals = @([regex]::Matches($on.vis.Text, '\d+(\.\d+)?') | ForEach-Object { [double]::Parse($_.Value, $inv) })
    $hits = @(25.0, 39.8, 50.1 | Where-Object { $want = $_; @($vals | Where-Object { [math]::Abs($_ - $want) -lt 0.05 }).Count -gt 0 }).Count
    $verdict = if ($hits -eq 3) { 'read right' } else { 'missed, it answered: ' + $on.vis.Text.Trim() }
    $lines += "vision check (fresh chat bars 25.0 / 39.8 / 50.1): $verdict"
}
if ($vulkan) {
    $vkd = Get-Vk
    $lines += "radeon: AMD Radeon beta, Vulkan device $($vkd.Name) ($($vkd.Desc), $($vkd.Total) MiB, $($vkd.Free) MiB free before the runs), vram from the GPU Adapter Memory counters"
    $lines += 'greedy text on Vulkan: no batch-invariant mode, so a different text with and without the head is expected'
}
$text = $lines -join "`r`n"
if ($vulkan) { $text = $text -replace 'n/a MiB', 'n/a' }
# Radeon: a short line that fits one post on X goes to the clipboard, the full block stays in the file for a pull request
$short = $null
if ($vulkan) {
    $size = if ($cfg.apu) { 'apu' } else { '{0}gb' -f [math]::Round([double]$cfg.gpuMiB / 1024) }
    # the README's names: 16k / 32k / 48k / 64k for those windows, thousands for the rest (131k, 195k, 262k)
    $window = 'n/a'
    if ($on.ctx) {
        $c = [int]$on.ctx
        $window = if ($c % 16384 -eq 0 -and $c -lt 131072) { '{0}k' -f ($c / 1024) } else { '{0}k' -f [math]::Round($c / 1000) }
    }
    $short = '{0} on my {1} {2} (windows, vulkan): {3} tok/s with the mtp head, {4} without, {5} context @sudoingX' -f `
        $vname.ToLower(), "$($cfg.gpuName)".ToLower(), $size, (Format-TokS $mOn), (Format-TokS $mOff), $window
    $text += "`r`n`r`nshort line for X:`r`n$short"
}
$file = Join-Path $here ('{0}-results-{1}.txt' -f $slug, (Get-Date -Format 'yyyyMMdd-HHmm'))
Set-Content -Path $file -Value $text -Encoding ASCII
try { Set-Clipboard -Value $(if ($short) { $short } else { $text }) } catch { }
Write-Host ''
Write-Host $text
Write-Host ''
if ($short) {
    Write-Host "Saved to $file. The short line for X is on your clipboard." -ForegroundColor Green
    Write-Host 'Share it: post the short line in a reply to @sudoingX, or open a pull request with the full block at github.com/sudoingX/local-ai-on-your-gaming-gpu'
} else {
    Write-Host "Saved to $file and copied to your clipboard." -ForegroundColor Green
    Write-Host 'Share it: paste it in a reply to @sudoingX, or open a pull request with your row at github.com/sudoingX/local-ai-on-your-gaming-gpu'
}
