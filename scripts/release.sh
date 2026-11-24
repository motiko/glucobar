#!/usr/bin/env bash
# Builds, signs, (if possible) notarizes and publishes a GlucoBar release, then updates
# the Homebrew cask so that `brew install motiko/tap/glucobar` picks it up.
#
# Signing: a "Developer ID Application" certificate is used if present, and the app is then
# notarized. Otherwise the "Apple Development" certificate is used without notarization, and
# the cask clears the quarantine flag after install so Gatekeeper doesn't block it.
#
# Usage:   scripts/release.sh <version>        e.g. scripts/release.sh 0.2.0
#
# One-time setup on the release Mac (1 and 2 only for notarized releases):
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarization credentials stored in the keychain under the profile name below:
#        xcrun notarytool store-credentials glucobar-notary --apple-id <id> --team-id <team>
#   3. gh authenticated with push access to this repo and the tap repo.
#
# Environment overrides: NOTARY_PROFILE, TAP_REPO, DRY_RUN=1 (build + notarize, publish nothing).
set -euo pipefail

VERSION=${1:?"usage: scripts/release.sh <version>"}
NOTARY_PROFILE=${NOTARY_PROFILE:-glucobar-notary}
TAP_REPO=${TAP_REPO:-motiko/homebrew-tap}
REPO=${REPO:-motiko/glucobar}
DRY_RUN=${DRY_RUN:-0}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3"
[[ -z $(git status --porcelain) ]] || die "working tree not clean; commit first"
git rev-parse "v$VERSION" >/dev/null 2>&1 && die "tag v$VERSION already exists"

IDENTITIES=$(security find-identity -v -p codesigning)
IDENTITY=$(grep -o '"Developer ID Application: [^"]*"' <<<"$IDENTITIES" | head -1 | tr -d '"' || true)
NOTARIZE=1
if [[ -z $IDENTITY ]]; then
  IDENTITY=$(grep -o '"Apple Development: [^"]*"' <<<"$IDENTITIES" | head -1 | tr -d '"' || true)
  NOTARIZE=0
  [[ -n $IDENTITY ]] || die "no 'Developer ID Application' or 'Apple Development' certificate in the keychain"
  echo "note: no Developer ID certificate; signing with Apple Development, NOT notarizing."
fi
TEAM=$(sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/' <<<"$IDENTITY")
if [[ $NOTARIZE == 1 ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notary profile '$NOTARY_PROFILE' missing (see setup above)"
fi

step "Version $VERSION"
BUILD_NUMBER=$(( $(git rev-list --count HEAD) + 1 ))
sed -i '' -E "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/(CFBundleVersion: )\"[^\"]*\"/\1\"$BUILD_NUMBER\"/" project.yml
xcodegen generate --quiet

step "Tests"
swift test --package-path GlucoBarCore >/dev/null

step "Build (universal, hardened runtime, signed by: ${IDENTITY%% (*})"
DERIVED=build/release
rm -rf "$DERIVED"
xcodebuild -project GlucoBar.xcodeproj -scheme GlucoBar -configuration Release \
  -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build -quiet
APP="$DERIVED/Build/Products/Release/GlucoBar.app"
codesign --verify --strict --deep "$APP"

mkdir -p dist
ZIP="dist/GlucoBar-$VERSION.zip"
rm -f "$ZIP"
if [[ $NOTARIZE == 1 ]]; then
  step "Notarize"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute "$APP"
  rm -f "$ZIP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "$ZIP  sha256 $SHA256"

if [[ $DRY_RUN == 1 ]]; then
  git checkout -- project.yml
  echo; echo "DRY_RUN: built $ZIP (notarized: $NOTARIZE); nothing committed or published."
  exit 0
fi

write_cask() {
  local postflight=""
  if [[ $NOTARIZE == 0 ]]; then
    postflight=$(cat <<'RUBY'

  # Not notarized: clear the quarantine flag so Gatekeeper doesn't block the app after
  # every install/upgrade. Removed once releases are signed with Developer ID.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/GlucoBar.app"]
  end
RUBY
)
  fi
  cat <<RUBY
cask "glucobar" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/GlucoBar-#{version}.zip"
  name "GlucoBar"
  desc "Menu bar app showing your current glucose from LibreLinkUp"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "GlucoBar.app"
$postflight

  uninstall quit: "dev.moti.glucobar"

  zap trash: "~/.config/glucobar"

  caveats <<~EOS
    GlucoBar is not a medical device. It uses an unofficial LibreLinkUp API that may stop
    working at any time, and it only alerts while your Mac is awake.
  EOS
end
RUBY
}

step "Commit, tag, GitHub release"
git commit -q -m "Release $VERSION" project.yml
git tag -a "v$VERSION" -m "GlucoBar $VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "GlucoBar $VERSION" \
  --notes "Install or upgrade: \`brew install motiko/tap/glucobar\` / \`brew upgrade glucobar\`"

step "Update Homebrew cask in $TAP_REPO"
TAP_DIR=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TAP_DIR" -- -q
mkdir -p "$TAP_DIR/Casks"
write_cask > "$TAP_DIR/Casks/glucobar.rb"
git -C "$TAP_DIR" add Casks/glucobar.rb
git -C "$TAP_DIR" commit -q -m "glucobar $VERSION"
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR"

echo; echo "Released $VERSION. Install with: brew install motiko/tap/glucobar"
