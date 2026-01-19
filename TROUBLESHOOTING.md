## Troubleshooting — Brrrrr

### Camera permission issues

- If the preview is black or shows “Camera Access Denied”, open **System Settings → Privacy & Security → Camera** and enable Brrrrr.
- You can also use the in-app “Open Privacy Settings” button.

### Launch at login not working

- If “Launch at login” shows **Requires approval**, open **System Settings → Login Items** and approve/enable Brrrrr.
- Some managed/work devices may restrict login items.

### Center Stage / camera effects errors in Console

macOS can print noisy camera pipeline logs (Center Stage / conferencing effects / DAL/CMIO). Brrrrr tries to avoid unsafe Center Stage toggling, but some logs are OS-level and don’t indicate app malfunction.

### High CPU usage

- Lower “Processing rate (FPS)” in Settings.
- Close other camera-using apps.
- Some external cameras or Continuity Camera configurations may be more expensive.

