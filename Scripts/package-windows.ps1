# Builds the Windows release (Rust UI in Desktop/, Swift engine in CrossPlatform/)
# and packages it as a zip in build\windows\dist.
#   pwsh Scripts/package-windows.ps1 -Version 0.15.0
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$settings = 'CrossPlatform/Sources/DraconisEngine/Settings.swift'
(Get-Content $settings) -replace 'static let version = "[^"]*"', "static let version = `"$Version`"" | Set-Content $settings
$cargo = 'Desktop/Cargo.toml'
$toml = Get-Content $cargo -Raw
$toml = ([regex]'(?m)^version = "[^"]*"').Replace($toml, "version = `"$Version`"", 1)
Set-Content $cargo $toml -NoNewline

# Swift's Clang 21 is older than the runner's MSVC STL expects.
$build = @('-c', 'release', '--package-path', 'CrossPlatform', '--build-system', 'native',
           '-Xcxx', '-D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH')
swift build @build --product draconis-engine
if ($LASTEXITCODE -ne 0) { throw "swift build failed" }
$bin = (swift build @build --show-bin-path).Trim()
cargo build --release --locked --manifest-path Desktop/Cargo.toml
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

$name = "Draconis-$Version-windows-x64"
$out = "build/windows/$name"
$dist = "build/windows/dist"
Remove-Item -Recurse -Force build/windows -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out, $dist | Out-Null

Copy-Item Desktop/target/release/draconis.exe "$out/Draconis.exe"
Copy-Item -Recurse Desktop/resources "$out/resources"
Copy-Item "$bin/draconis-engine.exe" $out
Get-ChildItem $bin -Filter *.dll | Copy-Item -Destination $out
Get-ChildItem $bin -Directory -Filter '*.resources' | Copy-Item -Destination $out -Recurse
Get-ChildItem $bin -Directory -Filter '*.bundle' | Copy-Item -Destination $out -Recurse

# The Swift runtime DLLs, from the toolchain's runtime folder.
$swift = (Get-Command swift).Source
$runtime = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Runtimes" -Directory -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending | Select-Object -First 1
if ($runtime) { Get-ChildItem "$($runtime.FullName)\usr\bin" -Filter *.dll | Copy-Item -Destination $out }
else { Get-ChildItem (Split-Path $swift) -Filter *.dll | Copy-Item -Destination $out }

Copy-Item LICENSE, THIRD-PARTY-NOTICES.md $out
@"
Draconis $Version for Windows

Run Draconis.exe. Keep the files in this folder together: Draconis.exe starts
draconis-engine.exe next to it.
"@ | Set-Content "$out/README.txt"

Compress-Archive -Path "$out/*" -DestinationPath "$dist/$name.zip" -Force
Get-FileHash "$dist/*.zip" -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path $_.Path -Leaf)" } |
  Set-Content "$dist/SHA256SUMS-windows"
Get-ChildItem $dist
