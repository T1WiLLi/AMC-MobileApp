#!/usr/bin/env bash
# Pipeline IPA ad hoc de LeGrenier : archive Release → export ad hoc (release-testing) → vérifications → release GitHub.
#
# Usage :
#   scripts/release/build-ipa.sh --team <TEAM_ID> [--version 1.0.0] [--build 42] [--release] [--draft] [--notes fichier.md]
#
#   --team      Équipe Apple payante (ad hoc impossible avec une « Personal Team »). Défaut : $GRENIER_TEAM_ID.
#   --version   Version affichée (CFBundleShortVersionString). Défaut : MARKETING_VERSION du projet.
#   --build     Numéro de build (CFBundleVersion). Défaut : nombre de commits sur HEAD (toujours croissant).
#   --method    release-testing (ad hoc, défaut) ou debugging (développement).
#   --bundle-id Bundle ID de l'app (défaut ca.amc2026.mobileapp). Le widget prend <bundle>.widgets, l'App Group group.<bundle>.
#   --firebase-plist  GoogleService-Info.plist de l'app Firebase qui correspond à ce bundle ID (défaut : celui du dépôt).
#
# Équipe du Cégep (6A6TQRFTWB) : ca.amc2026.mobileapp appartient à une autre équipe, donc
#   scripts/release/build-ipa.sh --team 6A6TQRFTWB --bundle-id ca.cegepsorel.legrenier \
#     --firebase-plist ../AMC-MobileApp-drafts/firebase-cegep/GoogleService-Info.plist --release
#   --release   Publie une release GitHub v<version>-<build> avec l'IPA (gh CLI connecté requis).
#   --draft     Avec --release : release en brouillon (visible seulement par les collaborateurs).
#   --notes     Fichier Markdown des notes de release (sinon générées depuis les commits).
#
# Prérequis : Xcode 26, compte de l'équipe connecté dans Xcode › Settings › Accounts,
# AMC-MobileApp/GoogleService-Info.plist présent (jamais commité), appareils de test enregistrés dans l'équipe.
# Tout ce qui est produit va dans build/release/ (ignoré par git).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

TEAM="${GRENIER_TEAM_ID:-}"
VERSION=""
BUILD=""
METHOD="release-testing"
BUNDLE_ID="ca.amc2026.mobileapp"
FIREBASE_PLIST=""
RELEASE=0
DRAFT=0
NOTES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --method) METHOD="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --firebase-plist) FIREBASE_PLIST="$2"; shift 2 ;;
    --release) RELEASE=1; shift ;;
    --draft) DRAFT=1; shift ;;
    --notes) NOTES="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

fail() { echo "✗ $*" >&2; exit 1; }
step() { printf '\n▸ %s\n' "$*"; }

[[ -n "$TEAM" ]] || fail "Équipe manquante : --team <TEAM_ID> ou GRENIER_TEAM_ID."
[[ "$METHOD" == "release-testing" || "$METHOD" == "debugging" ]] || fail "--method : release-testing ou debugging."
[[ -f AMC-MobileApp/GoogleService-Info.plist ]] || fail "AMC-MobileApp/GoogleService-Info.plist absent (voir docs/firebase.md)."
# Plist Firebase de la build : remplacé le temps du build si --firebase-plist, puis remis en place.
REPO_PLIST=AMC-MobileApp/GoogleService-Info.plist
if [[ -n "$FIREBASE_PLIST" ]]; then
  [[ -f "$FIREBASE_PLIST" ]] || fail "--firebase-plist introuvable : $FIREBASE_PLIST"
  cp "$REPO_PLIST" "$REPO_PLIST.pipeline-backup"
  restore_plist() { [[ -f "$REPO_PLIST.pipeline-backup" ]] && mv "$REPO_PLIST.pipeline-backup" "$REPO_PLIST"; }
  trap restore_plist EXIT
  cp "$FIREBASE_PLIST" "$REPO_PLIST"
fi
PLIST_BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$REPO_PLIST")
[[ "$PLIST_BUNDLE" == "$BUNDLE_ID" ]] || fail "Le plist Firebase est pour $PLIST_BUNDLE, pas $BUNDLE_ID (--firebase-plist)."
GOOGLE_SCHEME=$(/usr/libexec/PlistBuddy -c "Print :REVERSED_CLIENT_ID" "$REPO_PLIST" 2>/dev/null || true)
[[ -n "$GOOGLE_SCHEME" ]] || fail "REVERSED_CLIENT_ID absent du plist Firebase : Google Sign-In ne reviendrait pas dans l'app."
git ls-files --error-unmatch AMC-MobileApp/GoogleService-Info.plist >/dev/null 2>&1 && fail "GoogleService-Info.plist est suivi par git : retire-le avant de builder."
XCODE_VERSION=$(xcodebuild -version | sed -n 1p)
[[ "$XCODE_VERSION" == "Xcode 26"* ]] || fail "Xcode 26 requis ($XCODE_VERSION)."

PROJECT=AMC-MobileApp.xcodeproj
SCHEME=AMC-MobileApp
[[ -n "$VERSION" ]] || VERSION=$(grep -m1 'MARKETING_VERSION = ' "$PROJECT/project.pbxproj" | sed -E 's/.*= ([^;]+);/\1/')
[[ -n "$BUILD" ]] || BUILD=$(git rev-list --count HEAD)
COMMIT=$(git rev-parse --short HEAD)
TAG="v${VERSION}-${BUILD}"
OUT=build/release/$TAG
ARCHIVE=$OUT/LeGrenier.xcarchive
EXPORT=$OUT/ipa
mkdir -p "$OUT"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "⚠ Arbre de travail modifié : l'IPA ne correspondra pas exactement au commit $COMMIT."
fi

step "Packages Swift"
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME" >"$OUT/resolve.log" 2>&1 || { tail -20 "$OUT/resolve.log"; fail "résolution des packages"; }

step "Archive Release $VERSION ($BUILD), équipe $TEAM, bundle $BUNDLE_ID"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  GRENIER_BUNDLE_ID="$BUNDLE_ID" GRENIER_GOOGLE_URL_SCHEME="$GOOGLE_SCHEME" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  >"$OUT/archive.log" 2>&1 || { grep -E "error:|\*\* ARCHIVE" "$OUT/archive.log" | head -20; fail "archive (journal : $OUT/archive.log)"; }

step "Export $METHOD"
cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$METHOD</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>compileBitcode</key><false/>
  <key>stripSwiftSymbols</key><true/>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -allowProvisioningUpdates >"$OUT/export.log" 2>&1 || { grep -E "error|Error" "$OUT/export.log" | head -20; fail "export (journal : $OUT/export.log)"; }

IPA=$(ls "$EXPORT"/*.ipa | head -1)
[[ -f "$IPA" ]] || fail "aucun .ipa produit"
FINAL="$OUT/LeGrenier-$TAG.ipa"
mv "$IPA" "$FINAL"

step "Vérifications de l'IPA"
CHECK=$(mktemp -d)
trap 'rm -rf "$CHECK"; [[ -n "$FIREBASE_PLIST" ]] && restore_plist || true' EXIT
unzip -q "$FINAL" -d "$CHECK"
APP=$(ls -d "$CHECK"/Payload/*.app | head -1)
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist"; }
[[ "$(plist CFBundleIdentifier)" == "$BUNDLE_ID" ]] || fail "bundle ID inattendu : $(plist CFBundleIdentifier)"
[[ "$(plist GrenierAppGroup)" == "group.$BUNDLE_ID" ]] || fail "App Group inattendu : $(plist GrenierAppGroup)"
[[ "$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$APP/GoogleService-Info.plist")" == "$BUNDLE_ID" ]] || fail "plist Firebase embarqué pour un autre bundle"
plutil -p "$APP/Info.plist" | grep -q "$GOOGLE_SCHEME" || fail "schéma d'URL Google absent de l'Info.plist"
[[ "$(plist CFBundleShortVersionString)" == "$VERSION" ]] || fail "version inattendue"
[[ "$(plist CFBundleVersion)" == "$BUILD" ]] || fail "build inattendu"
[[ -f "$APP/GoogleService-Info.plist" ]] || fail "GoogleService-Info.plist absent de l'app : Firebase ne marcherait pas"
codesign --verify --deep --strict "$APP" || fail "signature invalide"
security cms -D -i "$APP/embedded.mobileprovision" >"$OUT/profile.plist" 2>/dev/null || fail "profil de provisionnement absent"
DEVICES=$(/usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$OUT/profile.plist" 2>/dev/null | grep -c '^ ' || true)
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$OUT/profile.plist")
EXPIRY=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$OUT/profile.plist")
SIZE=$(du -h "$FINAL" | cut -f1)
SHA=$(shasum -a 256 "$FINAL" | cut -d' ' -f1)
echo "✓ $FINAL ($SIZE)"
echo "  bundle $BUNDLE_ID · version $VERSION ($BUILD) · commit $COMMIT"
echo "  profil « $PROFILE_NAME » · $DEVICES appareil(s) · expire $EXPIRY"
echo "  sha256 $SHA"
echo "$SHA  $(basename "$FINAL")" >"$FINAL.sha256"

if [[ $RELEASE -eq 1 ]]; then
  step "Release GitHub $TAG"
  command -v gh >/dev/null || fail "gh CLI requis"
  if [[ -z "$NOTES" ]]; then
    NOTES="$OUT/notes.md"
    PREV=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
    {
      echo "Build ad hoc de LeGrenier **$VERSION ($BUILD)**, commit \`$COMMIT\`."
      echo
      echo "**Installation :** l'IPA ne s'installe que sur les iPhones enregistrés dans l'équipe ($DEVICES appareil(s) dans le profil « $PROFILE_NAME », valable jusqu'au $EXPIRY). iOS 26 requis."
      echo
      echo "SHA-256 : \`$SHA\`"
      echo
      echo "### Changements"
      if [[ -n "$PREV" ]]; then git log --no-merges --pretty='- %s' "$PREV..HEAD"; else git log --no-merges --pretty='- %s' -n 30; fi
    } >"$NOTES"
  fi
  FLAGS=(--title "LeGrenier $VERSION ($BUILD)" --notes-file "$NOTES" --target "$(git rev-parse HEAD)")
  [[ $DRAFT -eq 1 ]] && FLAGS+=(--draft)
  gh release create "$TAG" "$FINAL" "$FINAL.sha256" "${FLAGS[@]}"
  gh release view "$TAG" --json url -q .url
fi
