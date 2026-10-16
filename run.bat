@echo off
REM Double-click to run Tunefy with the build-time API keys (concerts, Gemini,
REM Pexels, YouTube) injected from the git-ignored secrets.json.
REM This is the same as: flutter run --dart-define-from-file=secrets.json
cd /d "%~dp0"
flutter run --dart-define-from-file=secrets.json
