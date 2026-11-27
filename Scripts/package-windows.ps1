# Builds the Windows release and packages it as a zip in build\windows\dist.
#   pwsh Scripts/package-windows.ps1 -Version 0.13.0
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$settings = 'CrossPlatform/Sources/DraconisCross/Settings.swift'
(Get-Content $settings) -replace 'static let version = "[^"]*"', "static let version = `"$Version`"" | Set-Content $settings

# Swift Build ignores platform conditions and compiles the GTK targets.
$env:SCUI_DEFAULT_BACKEND = 'WinUIBackend'
$build = @('-c', 'release', '--package-path', 'CrossPlatform', '--build-system', 'native')
swift build @build --product Draconis
if ($LASTEXITCODE -ne 0) { throw "swift build failed" }
$bin = (swift build @build --show-bin-path).Trim()

$name = "Draconis-$Version-windows-x64"
$out = "build/windows/$name"
$dist = "build/windows/dist"
Remove-Item -Recurse -Force build/windows -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out, $dist | Out-Null

Copy-Item "$bin/Draconis.exe" $out
Get-ChildItem $bin -Filter *.dll | Copy-Item -Destination $out
Get-ChildItem $bin -Directory -Filter '*.resources' | Copy-Item -Destination $out -Recurse
Get-ChildItem $bin -Directory -Filter '*.bundle' | Copy-Item -Destination $out -Recurse
Get-ChildItem $bin -Filter *.pri | Copy-Item -Destination $out

# The Swift runtime DLLs, from the toolchain's runtime folder.
$swift = (Get-Command swift).Source
$runtime = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Runtimes" -Directory -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending | Select-Object -First 1
if ($runtime) { Get-ChildItem "$($runtime.FullName)\usr\bin" -Filter *.dll | Copy-Item -Destination $out }
else { Get-ChildItem (Split-Path $swift) -Filter *.dll | Copy-Item -Destination $out }

Copy-Item LICENSE, THIRD-PARTY-NOTICES.md $out
@"
Draconis $Version for Windows

Run Draconis.exe. It needs the Windows App SDK runtime 1.5 or newer; if it
doesn't start, install it from https://aka.ms/windowsappsdk/1.5/latest/windowsappruntimeinstall-x64.exe
"@ | Set-Content "$out/README.txt"

Compress-Archive -Path "$out/*" -DestinationPath "$dist/$name.zip" -Force
Get-FileHash "$dist/*.zip" -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path $_.Path -Leaf)" } |
  Set-Content "$dist/SHA256SUMS-windows"
Get-ChildItem $dist
