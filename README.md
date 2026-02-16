# Copilot Quota (macOS menubar)

Small macOS menubar app that shows your GitHub Copilot premium request quota.

## Auth sources
The app tries, in order:
1. **VS Code** (`Code - Insiders`, `Code`, `VSCodium`) – reads the GitHub auth session from VS Code’s local storage + Keychain.
2. **GitHub CLI** (`gh auth token`)

If none work, the menubar UI shows a **Setup required** section with install/sign-in links.

### VS Code variants
Override the lookup order with:
```bash
COPILOT_QUOTA_VSCODE_PRODUCTS="Code - Insiders,Code" \
  /path/to/app
```

## Install (GitHub Releases)
1. Download the latest `*.zip` from **Releases**
2. Unzip
3. Move `Copilot Quota.app` to `/Applications`
4. Open it

## Build / run from source
```bash
swift build
swift run
```

## Package a .app bundle locally
```bash
bash scripts/package-app.sh
open "dist/Copilot Quota.app"
```

Optional overrides:
```bash
APP_NAME="Copilot Quota" \
BUNDLE_ID="dev.staticvar.copilot-quota-menubar" \
AUTHOR="staticvar" \
VERSION="1.2.3" \
bash scripts/package-app.sh
```

## Releasing
Tag a release:
```bash
git tag v1.2.3
git push --tags
```
The GitHub Actions workflow builds the `.app` and publishes `dist/*.zip` to the GitHub Release for that tag.

## Gatekeeper / notarization
For frictionless public distribution, macOS expects apps to be **code signed** and **notarized**.
Unsigned apps will typically require the user to explicitly allow opening them in macOS **Privacy & Security**.

