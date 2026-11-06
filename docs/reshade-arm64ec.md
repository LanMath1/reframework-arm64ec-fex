# Porting ReShade to ARM64EC — feasibility

Question: could a ReShade build run inside the game process on Armada/ARM64EC, so its add-ons (the
"NierASR"-style ones) could feed FSR 4 to the NPU?

Short answer: **no existing fork, and the port alone would not be enough** — the add-on we actually tested
is a closed x86-64 binary that would not load in an ARM64EC ReShade anyway.

---

## 1. Does a fork exist? No.

| search | result |
|---|---|
| `repo:crosire/reshade ARM64` (code) | 0 |
| `repo:crosire/reshade ARM64EC` (code) | 0 |
| global code search `ARM64EC reshade` | 0 |
| GitHub repos `reshade arm64` / `reshade arm` | 0 relevant (one "reshade-arma" for the game Arma) |

ReShade upstream is x86/x64 only. `CMakeLists.txt` derives the arch macro from pointer size:

```cmake
set_source_files_properties(... COMPILE_DEFINITIONS
  "$<IF:$<EQUAL:${CMAKE_SIZEOF_VOID_P},8>,_AMD64_,_X86_>;_WIN32_WINNT=_WIN32_WINNT_WIN7")
```

There is no ARM64 or ARM64EC branch anywhere in the tree.

## 2. The two hard blockers

### a. Hooking: MinHook is x86/x64 only

`source/hook.cpp` is a thin wrapper over MinHook, and every hook goes through it:

```cpp
const MH_STATUS status_code = MH_CreateHook(target, replacement, &trampoline);
```

MinHook's own description: *"The Minimalistic x86/x64 API Hooking Library for Windows"*. It decodes x86
instructions to build trampolines — meaningless for ARM64 code, and unusable for ARM64EC.

This is exactly the wall REFramework hit from the other side ([praydog/REFramework#1807](https://github.com/praydog/REFramework/issues/1807)):
writing an x86-64 inline hook into native ARM64EC code never gets emulated. We confirmed the workaround
(#1887) — **skip** those hooks entirely — which is not an option for ReShade: hooking `DXGI`/`D3D11` entry
points *is* the product.

A ReShade port would have to replace MinHook with an ARM64EC-capable hook engine. The precedent exists:
OptiScaler uses **Detours** (50 references upstream), and Detours supports ARM64EC — which is how
Sloptiscaler produces the ARM64EC `OptiScaler.dll` that Vela ships and that works on this device.

### b. The add-on ABI

ReShade add-ons are native DLLs that export `ReShadeCreateAddon` (`source/addon.hpp`); the host loads them
with `LoadLibrary`. Host and add-on must share the architecture.

The add-on that started this (`NierASR.addon64`, Nexus mod 843) is a **binary only** — no source. In an
ARM64EC ReShade it would have to be rebuilt as ARM64EC, which is impossible without the author.

So porting ReShade buys the *platform*, not the *upscaler*. The only add-ons that would work are the ones
rebuilt for ARM64EC.

## 3. What the port itself would take

| work item | note | rough effort |
|---|---|---|
| ARM64EC build target | MSVC `/arm64EC`, CMake arch plumbing, `_AMD64_` assumptions, 38 intrinsic sites to audit | 1–2 weeks |
| Replace MinHook with Detours | different API, trampoline semantics, ~all `hook::install()` call sites | 2–4 weeks |
| D3D11/D3D12/DXGI wrappers under ARM64EC | COM vtables are ABI-neutral, but export-forwarding and `CreateDevice` paths need testing on device | 1–2 weeks |
| Add-ons | needs ARM64EC add-ons; none exist | outside our control |
| Testing | Proton ARM64EC + FEX, one device | ongoing |

**Realistic total: 1–3 months of expert work, with a real chance of dead ends** in the D3D12/COM layer, for a
result that still cannot run the add-on that motivated it.

## 4. Why the payoff is small even if it worked

- Games with a native upscaler (DLSS/FSR2/XeSS) → already handled by Vela today.
- Games supported by REFramework with `TemporalUpscaler` (RE2, RE3, RE7, RE8, RE4 …) → **already proven
  working on this device** with the build in this repo; the remaining gap there is one line
  (`R16G16B16A16_SNORM`, see [feasibility.md](feasibility.md)).
- Games with neither (NieR: Automata) → the ReShade add-on route is the only one, and it needs both a
  ReShade ARM64EC port **and** an ARM64EC or source-available upscaler add-on.

## 5. Alternatives worth more than a ReShade port

1. **Host-native Vulkan layer.** ReShade has a Vulkan backend (`source/vulkan/vulkan.cpp`), and this platform
   already runs an aarch64 Linux Vulkan layer inside the game process (Vela's `VK_LAYER_VELA_npu`). A native
   layer has none of the ARM64EC problems. The catch: for a DX11 game under DXVK a layer sees the Vulkan
   device but not the game's depth/velocity buffers, so it cannot synthesise upscaler inputs on its own.
2. **REFramework/`TemporalUpscaler` as a first-class input** — the pragmatic answer, already demonstrated.
3. **Gamescope FSR 1** for the rest — what Vela itself documents today.

## Verdict

| route | viable? |
|---|---|
| existing ARM64EC ReShade fork | **none exists** |
| port ReShade to ARM64EC | possible but 1–3 months, and blocked at the add-on anyway |
| ReShade add-on for NieR | **not viable** without the add-on's source |
| REFramework route | viable, mostly done, one line away |
