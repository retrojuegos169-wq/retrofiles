param([switch]$TodoAntiguo)

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
$games = @()
$newCount = 0
$noCover = @()
$noTags = @()
$tagMap = @{}
$arcadeTitles = @{}

# Nombres reales de los juegos arcade (lista oficial de FBNeo, se descarga una sola vez)
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

# Etiquetas manuales (archivo etiquetas.txt, una linea por juego):
#   nombre del archivo sin extension | ETIQUETA1, ETIQUETA2
$tagsFile = Join-Path $root "etiquetas.txt"
if (Test-Path $tagsFile) {
    foreach ($line in [System.IO.File]::ReadAllLines($tagsFile)) {
        $line = $line.Trim()
        if ($line -eq "" -or $line.StartsWith("#") -or -not $line.Contains("|")) { continue }
        $parts = $line -split '\|', 2
        $key = $parts[0].Trim().ToLower()
        $values = @($parts[1].Split(",") | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ -ne "" })
        if ($key -ne "") { $tagMap[$key] = $values }
    }
    Write-Host "Etiquetas manuales cargadas: $($tagMap.Count) juegos"
}

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
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $key = $baseName.ToLower()

        if ($TodoAntiguo) {
            $added = "2020-01-01"
        } elseif ($previous.ContainsKey($path)) {
            $added = $previous[$path]
        } else {
            $added = $today
            $newCount++
        }

        $title = ""
        if ($isArcade -and $arcadeTitles.ContainsKey($key)) {
            $title = $arcadeTitles[$key]
        }

        $tags = @()
        if ($tagMap.ContainsKey($key)) {
            $tags = @($tagMap[$key])
        } else {
            $noTags += $baseName
        }

        $games += [pscustomobject]@{
            system = $consoleDir.Name
            file   = $file.Name
            path   = $path
            size   = [long]$file.Length
            added  = $added
            title  = $title
            tags   = $tags
        }

        if ($file.Length -gt 95MB) {
            Write-Host "AVISO: pesa mas de 95 MB (GitHub no acepta mas de 100 MB): $path"
        }

        if (-not (Has-Cover $consoleDir.Name $baseName)) {
            $noCover += "$coversName/$($consoleDir.Name)/$baseName.png"
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

# Lo que falta, con el nombre exacto que debe tener cada archivo
$report = @("PORTADAS QUE FALTAN ($($noCover.Count)). Crea cada archivo con este nombre (.png, .jpg o .webp):", "")
$report += $noCover
$report += ""
$report += "JUEGOS SIN ETIQUETAS MANUALES ($($noTags.Count)). Es opcional: la pantalla ya muestra la consola y la categoria automatica."
$report += $noTags
[System.IO.File]::WriteAllLines((Join-Path $root "catalogo-faltantes.txt"), $report, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "Listo: $($games.Count) juegos en el catalogo ($newCount nuevos, $($removed.Count) quitados)."
Write-Host "Juegos sin portada propia: $($noCover.Count) | sin etiquetas manuales: $($noTags.Count)"
Write-Host "Archivos creados: catalog.json y catalogo-faltantes.txt"
Read-Host "Pulsa Enter para cerrar"