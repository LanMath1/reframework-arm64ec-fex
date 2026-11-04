# Build REFramework (pd-upscaler + ARM64EC fix) on Windows.
# Requires: Visual Studio 2022 Build Tools (workload VCTools) + CMake + git.
#
#   powershell -ExecutionPolicy Bypass -File build-reframework.ps1
#
# Output:
#   build\bin\REFramework\dinput8.dll      -> the mod loader (drop in the game folder)
#   build\Release\PDPerfPlugin.dll         -> a DUMMY, do not use (see README)

param(
    [string]$WorkDir = "G:\rfbuild",
    [string]$CMake = ""
)

$ErrorActionPreference = "Stop"

if (-not $CMake) {
    $CMake = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Kitware.CMake_*" -Recurse -Filter cmake.exe -ErrorAction SilentlyContinue |
              Select-Object -First 1).FullName
    if (-not $CMake) { $CMake = "cmake" }
}

$repo = Join-Path $WorkDir "REFramework"

if (-not (Test-Path $repo)) {
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    git clone --filter=blob:none https://github.com/praydog/REFramework.git $repo
    git -C $repo submodule update --init --recursive --depth 1
}

# pd-upscaler + master (the ARM64EC hook fix). Conflict-free as of 2026-11.
git -C $repo checkout pd-upscaler
git -C $repo merge --no-edit origin/master

# CMake 4.4 cannot configure the project without a C# compiler; we do not need the C# API.
$toml = Join-Path $repo "cmake.toml"
(Get-Content $toml -Raw) -replace 'languages = \["CXX", "C", "CSharp"\]', 'languages = ["CXX", "C"]' |
    Set-Content $toml -NoNewline

$build = Join-Path $repo "build"
& $CMake -S $repo -B $build -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release
& $CMake --build $build --config Release --target REFramework pdperfmod

"dinput8.dll    -> $(Join-Path $build 'bin\REFramework\dinput8.dll')"
"PDPerfPlugin   -> $(Join-Path $build 'Release\PDPerfPlugin.dll') (dummy)"
