# YouTube Morphe

GitHub Actions downloads YouTube directly from APKMirror and patches it with MorpheApp patches.

- `main` reads `version.txt` and uses `MorpheApp/morphe-patches` branch `main`.
- `dev` reads `version_dev.txt` and uses `MorpheApp/morphe-patches` branch `dev`.
- APKMirror download logic is isolated in `scripts/download_youtube.js`.
- No dependency on `download_yt_synology`.
- No Playwright.
- APKMirror downloader uses wget and waits 15 seconds before looking for the download button and the final `here` link.

Files:
- `.github/workflows/patch.yml`
- `scripts/download_youtube.js`
- `version.txt`
- `version_dev.txt`
