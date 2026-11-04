# RE2 setup checklist (Armada / Odin 2 Portal)

Tested with:

- Armada `20261103.183b2c3`, kernel 7.2.6, Proton 11.0 (ARM64) + FEX
- Resident Evil 2, Steam appid `883710`, installed on SD card
- `dinput8.dll` from this repo's release
- PureDark UpscalerBasePlugin **1.1.2** (`PDPerfPlugin.dll`, 270848 bytes)
- Intel XeSS `libxess.dll`

## Files in the game folder

| File | Where it comes from |
|---|---|
| `dinput8.dll` | this repo (REFramework, merged build) |
| `PDPerfPlugin.dll` | UpscalerBasePlugin 1.1.2 (old file on Nexus, **not** 1.2.0) |
| `libxess.dll` | https://raw.githubusercontent.com/intel/xess/main/bin/libxess.dll |
| `re2_config.ini` | game — set `PCDXver=DirectX12`, `PCAntiAliasing=0`, `PCFidelityFXResolution=0` |

Nothing else is needed for XeSS through the upscaler. No Visual C++ runtime was required under Proton.

## Verify from the logs

`re2_framework_log.txt` in the game folder, look for:

```
Failed to hook ...: target is ARM64EC code     <- expected, this is the fix
[TemporalUpscaler] XeSS: Initialized.
[TemporalUpscaler] Wanted render resolution: 960x540
Successfully rendered with TemporalUpscaler
```

If instead you see `Upscale method N is not available` for all of 0/1/2, `PDPerfPlugin.dll` is the dummy
build from `pdperfmod` — replace it with PureDark 1.1.2.

## Turning it off

Delete `dinput8.dll`, `PDPerfPlugin.dll`, `libxess.dll` and the `reframework/` folder. The game returns to
its stock state (Steam → Properties → Installed Files → Verify integrity if in doubt).

## With Vela enabled (FSR 4 on the NPU)

Vela installs its OptiScaler as `dxgi.dll` and adds launch options:

```
VELA_NPU=1 VELA_NPU_LOG_FILE=.../npu/layer-883710.log WINEDLLOVERRIDES="dxgi=n,b" ... %command%
```

That part works: the layer loads and OptiScaler takes the XeSS calls. The FSR 4 provider then fails on the
motion-vector format (`VkFormat 92`), and Vela reports `FSR 4 did not start - SGSR 2 runs instead`.

Two practical notes:

- Vela owns `OptiScaler.ini` and rewrites it (`Spoofing.Dxgi` goes back to `true`) on launch, so hand
  edits do not survive. Change settings through the plugin.
- Do not switch the model while the game is running on this path: the backend change crashes inside
  `dxgi.dll`.
