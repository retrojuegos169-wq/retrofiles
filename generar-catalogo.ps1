# Genera catalog.json con la lista de juegos de la carpeta ROMS
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

function Find-Folder($name) {
    Get-ChildItem -Path $root -Directory |
        Where-Object { $_.Name -ieq $name } |
        Select-Object -First 1
}

$romsDir = Find-Folder "roms"
if (-not $romsDir) {
    Write-Host "No encuentro la carpeta ROMS junto a este script."
    Read-Host "Pulsa Enter para cerrar"
    exit 1
}
$coversDir = Find-Folder "covers"
$coversName = if ($coversDir) { $coversDir.Name } else { "COVERS" }

# Fechas de los juegos que ya estaban en el catalogo anterior
$catalogPath = Join-Path $root "catalog.json"
$previous = @{}
if (Test-Path $catalogPath) {
    try {
        $old = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($g in $old.games) { $previous[$g.path] = $g.added }
    } catch {
        Write-Host "Aviso: no pude leer el catalogo anterior, se creara de cero."
    }
}

$today = (Get-Date).ToString("yyyy-MM-dd")
# Nombres reales de los juegos arcade (lista oficial de FBNeo, se descarga una sola vez)
$arcadeTitles = @{}
$arcadeFolders = Get-ChildItem -Path $romsDir.FullName -Directory |
    Where-Object { ($_.Name.ToLower() -replace '[^a-z0-9]', '') -match 'arcade|fbneo|mame|neogeo' }
if ($arcadeFolders) {
    $datPath = Join-Path $env:TEMP "fbneo_arcade.dat"
    if (-not (Test-Path $datPath)) {
        try {
            Invoke-WebRequest -UseBasicParsing -OutFile $datPath -Uri "https://raw.githubusercontent.com/libretro/FBNeo/master/dats/FinalBurn%20Neo%20(ClrMame%20Pro%20XML%2C%20Arcade%20only).dat"
        } catch {
            Write-Host "Aviso: no pude descargar la lista de nombres arcade."
        }
    }
    if (Test-Path $datPath) {
        $text = [System.IO.File]::ReadAllText($datPath)
        $pattern = '<(?:game|machine)\s+name="([^"]+)"[^>]*>.*?<description>(.*?)</description>'
        foreach ($m in [regex]::Matches($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
            $arcadeTitles[$m.Groups[1].Value.ToLower()] = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
        }
        Write-Host "Nombres arcade cargados: $($arcadeTitles.Count)"
    }
}
$games = @()
$newCount = 0
$noCover = @()

function Has-Cover($system, $base) {
    if (-not $coversDir) { return $false }
    foreach ($ext in @(".png", ".jpg", ".jpeg", ".webp")) {
        if (Test-Path (Join-Path (Join-Path $coversDir.FullName $system) ($base + $ext))) { return $true }
    }
    return $false
}

foreach ($consoleDir in (Get-ChildItem -Path $romsDir.FullName -Directory | Sort-Object Name)) {
	    $isArcade = ($consoleDir.Name.ToLower() -replace '[^a-z0-9]', '') -match 'arcade|fbneo|mame|neogeo'
    foreach ($file in (Get-ChildItem -Path $consoleDir.FullName -File | Sort-Object Name)) {
        if ($file.Name -like "*.part") { continue }

        $path = "$($romsDir.Name)/$($consoleDir.Name)/$($file.Name)"
        if ($previous.ContainsKey($path)) {
            $added = $previous[$path]
        } else {
            $added = $today
            $newCount++
        }
	        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $title = ""
        if ($isArcade -and $arcadeTitles.ContainsKey($baseName.ToLower())) {
            $title = $arcadeTitles[$baseName.ToLower()]
        }
        $games += [pscustomobject]@{
            system = $consoleDir.Name
            file   = $file.Name
            path   = $path
            size   = [long]$file.Length
            added  = $added
	    title  = $title
        }

        if ($file.Length -gt 95MB) {
            Write-Host "AVISO: pesa mas de 95 MB (GitHub no acepta mas de 100 MB): $path"
        }

        $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if (-not (Has-Cover $consoleDir.Name $base)) {
            $noCover += "$coversName/$($consoleDir.Name)/$base.png"
        }
    }
}

$removed = @($previous.Keys | Where-Object { $games.path -notcontains $_ })

$catalog = [pscustomobject]@{
    version = 1
    updated = $today
    games   = $games
}
$json = $catalog | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($catalogPath, $json, (New-Object System.Text.UTF8Encoding $false))

# Portadas que faltan, con el nombre exacto que deben tener
$report = @("PORTADAS QUE FALTAN ($($noCover.Count)). Crea cada archivo con este nombre (.png, .jpg o .webp):", "")
$report += $noCover
[System.IO.File]::WriteAllLines((Join-Path $root "catalogo-faltantes.txt"), $report, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "Listo: $($games.Count) juegos en el catalogo ($newCount nuevos, $($removed.Count) quitados)."
Write-Host "Juegos sin portada propia: $($noCover.Count) (ver catalogo-faltantes.txt)"
Read-Host "Pulsa Enter para cerrar"