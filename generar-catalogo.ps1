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
$snapsDir = Find-Folder "snaps"
$descDir = Find-Folder "descriptions"

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
$noSnap = @()
$noDesc = @()

function Has-Any($dir, $system, $base, $suffixes) {
    if (-not $dir) { return $false }
    foreach ($s in $suffixes) {
        if (Test-Path (Join-Path (Join-Path $dir.FullName $system) ($base + $s))) { return $true }
    }
    return $false
}

foreach ($consoleDir in (Get-ChildItem -Path $romsDir.FullName -Directory | Sort-Object Name)) {
    foreach ($file in (Get-ChildItem -Path $consoleDir.FullName -File | Sort-Object Name)) {
        if ($file.Name -like "*.part") { continue }

        $path = "$($romsDir.Name)/$($consoleDir.Name)/$($file.Name)"
        if ($previous.ContainsKey($path)) {
            $added = $previous[$path]
        } else {
            $added = $today
            $newCount++
        }

        $games += [pscustomobject]@{
            system = $consoleDir.Name
            file   = $file.Name
            path   = $path
            size   = [long]$file.Length
            added  = $added
        }

        if ($file.Length -gt 95MB) {
            Write-Host "AVISO: pesa mas de 95 MB (GitHub no acepta mas de 100 MB): $path"
        }

        $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if (-not (Has-Any $coversDir $consoleDir.Name $base @(".png", ".jpg", ".jpeg", ".webp"))) { $noCover += $path }
        if (-not (Has-Any $snapsDir $consoleDir.Name $base @(".snap.png"))) { $noSnap += $path }
        if (-not (Has-Any $descDir $consoleDir.Name $base @(".txt"))) { $noDesc += $path }
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

# Lista de lo que falta, para completarlo
$report = @()
$report += "SIN PORTADA ($($noCover.Count))"
$report += $noCover
$report += ""
$report += "SIN CAPTURA ($($noSnap.Count))"
$report += $noSnap
$report += ""
$report += "SIN DESCRIPCION ($($noDesc.Count))"
$report += $noDesc
[System.IO.File]::WriteAllLines((Join-Path $root "catalogo-faltantes.txt"), $report, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "Listo: $($games.Count) juegos en el catalogo ($newCount nuevos, $($removed.Count) quitados)."
Write-Host "Sin portada: $($noCover.Count) | sin captura: $($noSnap.Count) | sin descripcion: $($noDesc.Count)"
Write-Host "Archivos creados: catalog.json y catalogo-faltantes.txt"
Read-Host "Pulsa Enter para cerrar"