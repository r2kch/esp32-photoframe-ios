# PhotoFrameUploader iOS App for aitjcize/esp32-photoframe

## Run on iPhone (free Apple ID)
1. Open `PhotoFrameUploader/PhotoFrameUploader.xcodeproj` in Xcode.
2. Select your iPhone as the run target.
3. Xcode will prompt for signing; choose a free Apple ID.
4. Click Run.

## Notes
- Default album is `Default` and processing mode is `enhanced`.
- The app uses HTTP to reach the device, so it includes an ATS exception and local network usage description.
- If you change the device host, it is saved on-device.
