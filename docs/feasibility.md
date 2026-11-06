# Feasibility of what we proposed in vela#1

Scope: the proposal in [zrprod9-cmyk/vela#1](https://github.com/zrprod9-cmyk/vela/issues/1) (support games with
no native upscaler, by hosting the fork as a ReShade add-on and feeding `VK_LAYER_VELA_npu`) plus the two asks
added in the comment (MV format, crash on backend switch).

Measured on: AYN Odin 2 Portal (SM8550 / Adreno 740 / HTP v73), Armada `20261103.183b2c3`, Proton 11.0 (ARM64) + FEX.

## The decisive factor: the source is all there

| piece | source in the repo | build |
|---|---|---|
| OptiScaler fork | `fork/patches/` — 21 patches on `justradical/Sloptiscaler` `f80e4da3` (= upstream OptiScaler 10.0.0.1) | `fork/build/build.sh out` → `OptiScaler.dll` (ARM64EC), Docker + x86-64 host |
| FSR 4 VK provider | `provider/` — full fsr4vk + Vela overlay, reproducible (md5 `d230a12…`) | `provider/build.sh` |
| NPU layer | `npu-layer/` — `vela_npu_layer.cpp`, build 11 | `npu-layer/build.sh` (Docker, aarch64 cross) |
| daemon | `npu/src/` — `fsr4npud.cpp` | `npu/src/build.sh` |

Nothing is a binary blob except AMD's FSR 4 assets (MIT) and Qualcomm's QNN runtime. **Every proposal below is
patchable by a third party.**

---

## 1. RE2 motion-vector format — **HIGH feasibility** (one line)

### What happens

```
[I] MvInit Vela FSR 4 VK: MV pass ready (960x540 RG16F, render px)
[E] Unsupported Vela FSR 4 VK: motion vectors (MV pass) format VkFormat 92 is not one the provider takes
```

`VkFormat 92` is `VK_FORMAT_R16G16B16A16_SNORM` (verified against `vulkan_core.h`).

### Where

`Fsr4VkBridge.h`, `MvSourceView()` (introduced by `fork/patches/0019-vela-fsr4-mv-pass.patch`):

```cpp
switch (src.fmt)
{
case VK_FORMAT_R16G16_SFLOAT:
case VK_FORMAT_R32G32_SFLOAT:
case VK_FORMAT_R16G16B16A16_SFLOAT:
case VK_FORMAT_R32G32B32A32_SFLOAT:
case VK_FORMAT_R16G16_SNORM:
case VK_FORMAT_R8G8_SNORM:
    break;
default:
    return VK_NULL_HANDLE;          // <- RE2's MV lands here
}
```

The list already has the **2-channel** SNORM (`78`) and the **4-channel** FLOAT (`97`), but not the 4-channel
SNORM (`92`). The MV pass shader is format-agnostic in that respect: it is already fed RGBA16F (`97`) in other
games, so it reads `.rg` from a vec4.

### The patch

```diff
         case VK_FORMAT_R16G16_SNORM:
+        case VK_FORMAT_R16G16B16A16_SNORM:
         case VK_FORMAT_R8G8_SNORM:
```

### Why it should work

- SNORM sampling normalises to float exactly like the 2-channel path that is already accepted; the `.rg` lanes
  carry the same numbers.
- REF's `TemporalUpscaler` presents its MV target as a 4-channel SNORM image (that is where 92 comes from), so
  this is a format alias, not a new data layout.
- No shader change, no new resource, no ABI change.

### Cost

| step | effort |
|---|---|
| patch | 1 line |
| build the fork | `fork/build/build.sh out` — Docker, x86-64 host, ~15 min |
| install | replace `OptiScaler.dll` as `dxgi.dll` in the game folder (Vela's backup machinery handles the rest) |
| test | one launch, check `layer-883710.log` for `jobs, HTP … ms` |

**Blocker on our side:** the build host here has neither Docker nor WSL. The author (or anyone with Docker) can
produce this in one command.

### Risk

Low. Worst case the MV pass produces wrong vectors for this game and FSR 4 looks smeared — the existing
`SGSR 2` fallback still catches a hard failure.

---

## 2. Crash when switching the model while the game runs — **MEDIUM**

`fsr4` ↔ `fsr4fast` with the game open kills the process; REF's handler writes `reframework_crash.dmp` and names
`dxgi.dll` as the module. The switch path is `ChangeFeature` (patch `0018`/`0010`, live-settings), after the
FSR 4 dispatch has already failed once.

It needs the fork source plus a debug build to pin down (likely a use-after-free when the bridge is recreated
while a frame is in flight), not just a log read.

**Workaround today:** choose the model before launching; Vela's live switch is the only thing that triggers it.

Priority: cosmetic for this path, because once #1 is fixed the fallback (and therefore the switch) stops being
exercised on every frame.

---

## 3. The ReShade add-on route from the issue — **LOW on ARM64EC**

This is the part of the proposal that does not survive contact with the platform.

1. **Architecture.** In Proton ARM64EC the game is x86-64 under FEX while system DLLs (`dxgi`, `dinput8`) are
   native ARM64EC. Vela's fork is built **ARM64EC** for exactly that reason — it replaces `dxgi.dll`.
   ReShade has no ARM64EC build: the add-on would have to be loaded by an x86-64 ReShade, which cannot take the
   ARM64EC `dxgi.dll` slot. Making it work means first porting ReShade to ARM64EC.
2. **Hook point.** ReShade's add-on API gives you the swapchain and a device, not the depth/velocity of the
   game's rendering. NierASR works because it hooks the game's own draw calls. Reaching OptiScaler's input set
   from there is a new subsystem, not a build flag.
3. **A better vehicle already exists and is proven.** REFramework's `TemporalUpscaler` synthesises exactly those
   inputs (it is what PureDark's upscaler did), and we demonstrated the full chain
   `TemporalUpscaler → XeSS → OptiScaler → VK_LAYER_VELA_npu` running on this device. The remaining gap there is
   one line (§1), not a port.

### Recommended reframing of the issue

> Support **REFramework's `TemporalUpscaler` (and its XeSS/DLSS backends) as an upscaler input** — i.e. treat a
> game that has no native upscaler but has REF upscaling as a normal OptiScaler input.

That covers RE2, RE3, RE7, RE8, RE4 and everything else REF supports, with no new injection layer. For a game
with neither REF nor a native upscaler (NieR: Automata), the honest answer stays "Gamescope FSR 1" until a
ReShade ARM64EC build exists.

---

## Order of work

| # | item | effort | payoff |
|---|---|---|---|
| 1 | `VK_FORMAT_R16G16B16A16_SNORM` in `MvSourceView` | 1 line + build | RE2 gets FSR 4 on the NPU |
| 2 | Don't tear down the bridge from `ChangeFeature` | debugging | no crash on live switch |
| 3 | REF/TemporalUpscaler as a first-class input | documentation + profiles | games without native upscalers |
| 4 | ReShade add-on | port ReShade to ARM64EC | marginal, after 1–3 |
