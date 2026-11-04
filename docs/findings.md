# Findings

Everything below was measured on an AYN Odin 2 Portal (SM8550, Adreno 740, HTP v73) running Armada
`20261103.183b2c3`, Proton 11.0 (ARM64) + FEX.

---

## 1. AYN Odin 2 Portal: REFramework does not survive on ARM64EC

Every `pd-upscaler` build crashed a few seconds after launch, before any upscaler code ran.

```
[13:36:06.873] [MethodDatabase] Building method address map...
[13:36:07.037] [error] Call stack: ... DINPUT8.dll + 0x5f9508 ...
[13:36:07.081] Module: 6ffff8230000 C:\windows\system32\dinput8.dll
```

The call stack contains frames in `C:\windows\system32\dinput8.dll` — native ARM64EC code. REFramework's
`DInputHook` writes an x86-64 inline `jmp` into `GetDeviceState`, FEX never emulates it, and the process
dies.

Reproduced with:

| Build | Commit | Result |
|---|---|---|
| `pd-upscaler` nightly | 8c209b1f (2026-10-11) | crash |
| release v1.5.9.1 | older | crash |
| `master` nightly | f9cb2ac3 (2026-11-03, #1887) | **runs** |

The fix ([#1887](https://github.com/praydog/REFramework/pull/1887)) checks `RtlIsEcCode` before hooking
and skips the hook with a log line. It only landed on `master`; `pd-upscaler` had not been rebased.

---

## 2. Merging master into pd-upscaler is clean

```
git checkout pd-upscaler          # 8c209b1f
git merge origin/master           # f9cb2ac3
Auto-merging shared/sdk/Renderer.cpp
Automatic merge went well
```

No conflicts. The only build change needed was dropping the `CSharp` language from `cmake.toml`, because
CMake 4.4 aborts with:

```
CMake Error at CMakerLists.txt:32 (project): No CMAKE_CSharp_COMPILER could be found.
```

The C# API is irrelevant to the DLL.

---

## 3. `pdperfmod` is a dummy, and it freezes the game

`cmake.toml` says:

```toml
[target.pdperfmod]
sources = ["dependencies/pd-perfmod/dummy/**.cpp"]
```

Its strings contain no `nvngx`, `libxess`, `ffx`, `DLSS`, `FSR` or `XeSS` — only the interface
(`InitUpscaler`, `IsUpscaleMethodAvailable`, ...).

Behaviour with it installed:

```
[TemporalUpscaler] Upscale method 0 is not available
[TemporalUpscaler] Upscale method 1 is not available
[TemporalUpscaler] Upscale method 2 is not available
[TemporalUpscaler] No upscale methods are available, TemporalUpscaler will not work
```

and then, every ~11 s, forever:

```
Sending rehook request for D3D
Unhooking D3D12 / Hooking D3D12
[Streamline] Failed to get sl.dlss_g.dll module handle
```

which presents as the game freezing. With the real `PDPerfPlugin.dll` (PureDark 1.1.2) the loop count is
**0** and the upscaler initializes.

---

## 4. RE2 + TemporalUpscaler + XeSS works

```
[TemporalUpscaler] Creating UpscaleMethod_XeSS
[TemporalUpscaler] XeSS: Version - 2.0.2
[TemporalUpscaler] XeSS: XeSS context created. Result - Success.
[TemporalUpscaler] XeSS: Initialized.
[TemporalUpscaler] Upscaled texture size: 1920x1080
[TemporalUpscaler] Wanted render resolution: 960x540
Successfully rendered with TemporalUpscaler
```

No rehook loop, no crash. XeSS runs on the Adreno GPU through vkd3d-proton — functional, but slow.

---

## 5. Vela / FSR 4 on the NPU: one format away

Vela (OptiScaler fork + `VK_LAYER_VELA_npu`) does hook the XeSS input:

```
Poll Vela live (Z:\tmp\vela-live\883710.ini): model fsr4 ... npu 2
TryEvaluateOptiFeature Vela live: handle 1000002 model fsr4 -> SGSR 3
ChangeFeature changing backend to SGSR 3
InitInternal Initializing SGSR3 960x540 -> 1920x1080
```

and the NPU layer is alive in the game process:

```
[vela-npu 56205 ...] device created (layer build 11): dma-buf import on
```

The FSR 4 provider then rejects the motion vectors:

```
[I] MvInit Vela FSR 4 VK: MV pass ready (960x540 RG16F, render px)
[E] Unsupported Vela FSR 4 VK: motion vectors (MV pass) format VkFormat 92
    is not one the provider takes
[E] EvaluateFsr4 SGSR3: FSR 4 VK frame failed; SGSR 2 from the next frame
[E] EvaluateInternal SGSR3: the student failed; v1f from the next frame
[W] TryEvaluateOptiFeature Vela live: fsr4 cannot run in this game; SGSR 2 instead
```

Same with `model fsr4fast` and `model fsr4`. Switching between them with the game running crashes inside
`dxgi.dll` (OptiScaler's `ChangeFeature` path), with REF's handler writing the dump.

So the chain
`TemporalUpscaler → XeSS → OptiScaler → VK_LAYER_VELA_npu → fsr4npud`
is complete except for the MV format conversion.

---

## 6. NieR: Automata — a different dead end (for the record)

NieR has **no** DLSS / FSR 2-3 / XeSS at all, so Vela has nothing to intercept and stays on
"SGSR 2 waiting for the first frame" (confirmed in `OptiScaler.log`: it tries `HookFSR2ExeInputs` /
`HookFSR3ExeInputs` and hooks nothing).

A ReShade add-on (NierASR 0.9.6, Nexus mod 843) does create the calls, and it loaded and injected
(592 of 600 frames) with Vela's `amd_fidelityfx_dx12.dll` as the provider — but it runs AMD's DX12 FSR
through a DX11↔DX12 shared-texture bridge:

```
WARNING perf: FSR dispatch alone costs 5.40 ms per frame at 1280x720 (native resolution, no upscaling gain)
GPU frame 30.98 = before-mod 23.10 + mod 7.23 + after-mod 0.65
diag CPU: ReShade + Present call 15.46 ms (47% of the frame)
fps: 55.8 -> 30.3
```

plus a white image with horizontal lines (invalid shared texture on Turnip: `native 16-bit shader ops: no`).
And the game presents the same size it renders, so the "upscale" is 1:1 — cost without benefit.

Conclusion: for games with no native upscaler the useful architecture is the one this repo enables —
REFramework/ReShade creates the inputs, and the NPU does the network — **not** a DX12 compute bridge on
Adreno.
