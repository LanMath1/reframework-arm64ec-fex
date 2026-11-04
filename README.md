# REFramework on ARM64EC / FEX — build + findings

Building **REFramework** for Linux-on-ARM handhelds (Armada / SteamOS-like, Snapdragon + Adreno via
FEX + Proton ARM64EC), and what that unlocks and where it still breaks.

**TL;DR**

- `pd-upscaler` (the branch with `TemporalUpscaler`) had no ARM64EC fix → crashed on every launch
  ([#1807](https://github.com/praydog/REFramework/issues/1807)).
- The fix ([#1887](https://github.com/praydog/REFramework/pull/1887), merged 2026-11-03) exists on
  `master` only; `pd-upscaler` was 3 weeks behind.
- This repo merges the two, patches the build for a CMake 4 host, and ships the resulting
  `dinput8.dll`.
- With it, **Resident Evil 2 runs on an AYN Odin 2 Portal with `TemporalUpscaler` + XeSS active**
  (960x540 → 1920x1080), and Vela's OptiScaler intercepts it.
- The last step — FSR 4 on the Hexagon NPU — still fails inside Vela's provider: it rejects the
  motion-vector format (`VkFormat 92`) that the `TemporalUpscaler` path produces.

## Test device

| | |
|---|---|
| Device | AYN Odin 2 Portal (`ayn,odin2portal`) |
| SoC | Snapdragon 8 Gen 2 / SM8550, Adreno 740, Hexagon HTP v73 |
| OS | Armada `20261103.183b2c3` (Fedora 44 base), kernel 7.2.6 aarch64 |
| Runtime | Proton 11.0 (ARM64) + FEX + pressure-vessel, Steam Linux Runtime 4 arm64 |
| Game | Resident Evil 2 (Steam appid 883710), RE Engine, DX12 |

"Proton ARM64EC" here means system DLLs such as `system32\dinput8.dll` are native ARM64EC code, while the
game and the mods are x86-64 translated by FEX. Inline x86-64 hooks written into those DLLs are never
emulated — that is the whole bug.

## What was built

```
base:      praydog/REFramework @ pd-upscaler 8c209b1f79  (2026-10-11)
merged:    praydog/REFramework @ master      f9cb2ac392  (2026-11-03, "Skip inline hooks on ARM64EC code")
result:    725b609  "Merge master (incl. #1887 ARM64EC hook fix) into pd-upscaler"
```

The merge is **conflict-free** (`Auto-merging shared/sdk/Renderer.cpp`, then clean).

One build-system patch is needed because this build host has no C# compiler and CMake 4.4 refuses to
configure the project without one. The C# API is not needed for the DLL:

```patch
-languages = ["CXX", "C", "CSharp"]
+languages = ["CXX", "C"]
```

Toolchain used: Visual Studio 2022 Build Tools 17.14.44 (MSVC 19.44.35229), Windows SDK 10.0.26100,
CMake 4.4.4.

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --target REFramework pdperfmod
```

Targets are **monolithic** now — there is no per-game `RE2.vcxproj` any more:

| Target | Output | Notes |
|---|---|---|
| `REFramework` | `build/bin/REFramework/dinput8.dll` | the mod loader + `TemporalUpscaler` |
| `pdperfmod` | `build/Release/PDPerfPlugin.dll` | **a dummy** — see below |

⚠️ `pdperfmod` is `dependencies/pd-perfmod/dummy/PDPerfPlugin.cpp`: it exports the interface and
returns "not available" for every upscaler. REF loads it happily and then upscales nothing, which also
puts it into a D3D12 rehook loop every ~11 s (this looks like a freeze). The real backend is still
PureDark's **UpscalerBasePlugin 1.1.2** (`PDPerfPlugin.dll`, 270848 bytes).

## Results in Resident Evil 2

With `dinput8.dll` from this repo + PureDark's `PDPerfPlugin.dll` + Intel's `libxess.dll`:

```
[error] Failed to hook 6ffff8242660: target is ARM64EC code     <- the fix, working as intended
[info]  DInputHook failed to hook.
...
[TemporalUpscaler] Creating UpscaleMethod_XeSS
[TemporalUpscaler] XeSS: XeSS context created. Result - Success.
[TemporalUpscaler] Upscaled texture size: 1920x1080
[TemporalUpscaler] Wanted render resolution: 960x540
Successfully rendered with TemporalUpscaler
```

No crash, no rehook loop. XeSS runs through vkd3d-proton on the Adreno GPU — it works, but it is slow,
because it is GPU compute on a mobile GPU.

### Then Vela's OptiScaler, and where it stops

Vela installs OptiScaler as `dxgi.dll` for the game; it does pick up the XeSS calls that
`TemporalUpscaler` makes, and Vela's Vulkan layer loads inside the game process:

```
[vela-npu 56205 ...] device created (layer build 11): dma-buf import on
```

but the FSR 4 provider refuses the motion vectors:

```
[I] MvInit Vela FSR 4 VK: MV pass ready (960x540 RG16F, render px)
[E] Unsupported Vela FSR 4 VK: motion vectors (MV pass) format VkFormat 92
    is not one the provider takes
[E] EvaluateFsr4 SGSR3: FSR 4 VK frame failed; SGSR 2 from the next frame
[W] TryEvaluateOptiFeature Vela live: fsr4 cannot run in this game; SGSR 2 instead
```

Identical for `model fsr4` and `model fsr4fast`, so it is not a preset problem. Switching models while
the game is running then crashes inside `dxgi.dll` (OptiScaler), dump written by REF's handler.

Details, per experiment: [docs/findings.md](docs/findings.md).

## Install (RE2 on Armada)

1. `dinput8.dll` (from the release) → game folder
2. PureDark's **UpscalerBasePlugin 1.1.2** `PDPerfPlugin.dll` → game folder
   (1.2.0 does not load the backend)
3. `libxess.dll` (Intel XeSS) → game folder
4. In game: DX12, anti-aliasing OFF

See [docs/re2-setup.md](docs/re2-setup.md) for the full checklist and how to revert.

## Downloads

`dinput8.dll` built from `725b609` is attached to the release. MIT, same as upstream REFramework.

## Credits

- [praydog/REFramework](https://github.com/praydog/REFramework) (MIT) — and the #1887 fix, tested by
  The412Banner on the same class of device
- PureDark — UpscalerBasePlugin
- Intel — XeSS
- Vela (`zrprod9-cmyk/vela`) — OptiScaler fork, NPU layer, `fsr4npud`
