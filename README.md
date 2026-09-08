# Personal Life & Seva Assistant

A Flutter starter app for a customizable personal assistant:
- Water tracking
- Custom activities
- Reusable checklists
- Suggested activities
- Seva/spiritual activities
- Simple accounts/ledger
- Dashboard
- Live outdoor weather and scheduled local reminders
- GitHub Release APK update prompt

## Run
1. Install Flutter SDK.
2. Open this folder in VS Code.
3. Run `flutter pub get`
4. Run `flutter run`

Indoor temperature is entered manually because typical phones do not expose an ambient room-temperature sensor. Live outdoor temperature uses the device location and Open-Meteo after location permission is granted.

To deliver updates directly from GitHub, create a Release with tag names such as `v0.1.1+2` and attach an APK named `app-release.apk`. The installed app checks `pbrundha1-design/personal-life-seva-assistant`, asks before downloading, and opens Android's installer. Android may require the user to allow this app to install unknown apps once.
