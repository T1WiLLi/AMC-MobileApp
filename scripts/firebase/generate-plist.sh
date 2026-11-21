#!/usr/bin/env bash
# Génère AMC-MobileApp/GoogleService-Info.plist à partir du .env (voir docs/firebase.md).
# Usage : scripts/firebase/generate-plist.sh [chemin/.env] [chemin/sortie.plist]
# Le .env et le plist sont ignorés par git : ne jamais les committer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${1:-$ROOT/.env}"
OUT="${2:-$ROOT/AMC-MobileApp/GoogleService-Info.plist}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ $ENV_FILE introuvable. Copie .env.example en .env et remplis-le (docs/firebase.md)." >&2
  exit 1
fi

# Lecture KEY=VALUE sans exécuter le fichier (pas de `source`).
read_var() {
  local line
  line="$(grep -E "^[[:space:]]*$1=" "$ENV_FILE" | tail -n 1 || true)"
  line="${line#*=}"
  line="${line%$'\r'}"
  line="${line#\"}"; line="${line%\"}"
  line="${line#\'}"; line="${line%\'}"
  printf '%s' "$line"
}

REQUIRED=(FIREBASE_PROJECT_ID FIREBASE_BUNDLE_ID FIREBASE_API_KEY FIREBASE_GCM_SENDER_ID
          FIREBASE_GOOGLE_APP_ID FIREBASE_CLIENT_ID FIREBASE_REVERSED_CLIENT_ID FIREBASE_STORAGE_BUCKET)
missing=()
for key in "${REQUIRED[@]}"; do
  value="$(read_var "$key")"
  if [[ -z "$value" ]]; then missing+=("$key"); fi
  if [[ "$value" == *[\<\>\&]* ]]; then
    echo "❌ $key contient un caractère interdit (<, > ou &)." >&2; exit 1
  fi
  printf -v "$key" '%s' "$value"
done
if (( ${#missing[@]} )); then
  echo "❌ Valeurs manquantes dans $ENV_FILE : ${missing[*]}" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CLIENT_ID</key>
	<string>$FIREBASE_CLIENT_ID</string>
	<key>REVERSED_CLIENT_ID</key>
	<string>$FIREBASE_REVERSED_CLIENT_ID</string>
	<key>API_KEY</key>
	<string>$FIREBASE_API_KEY</string>
	<key>GCM_SENDER_ID</key>
	<string>$FIREBASE_GCM_SENDER_ID</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>$FIREBASE_BUNDLE_ID</string>
	<key>PROJECT_ID</key>
	<string>$FIREBASE_PROJECT_ID</string>
	<key>STORAGE_BUCKET</key>
	<string>$FIREBASE_STORAGE_BUCKET</string>
	<key>IS_ADS_ENABLED</key>
	<false></false>
	<key>IS_ANALYTICS_ENABLED</key>
	<false></false>
	<key>IS_APPINVITE_ENABLED</key>
	<true></true>
	<key>IS_GCM_ENABLED</key>
	<true></true>
	<key>IS_SIGNIN_ENABLED</key>
	<true></true>
	<key>GOOGLE_APP_ID</key>
	<string>$FIREBASE_GOOGLE_APP_ID</string>
</dict>
</plist>
PLIST

plutil -lint "$OUT" >/dev/null 2>&1 || { echo "❌ plist invalide : $OUT" >&2; exit 1; }
echo "✅ $OUT généré pour le projet $FIREBASE_PROJECT_ID."

# Le schéma d'URL Google Sign-In doit être égal à REVERSED_CLIENT_ID.
if ! grep -q "<string>$FIREBASE_REVERSED_CLIENT_ID</string>" "$ROOT/Config/AMC-MobileApp-Info.plist"; then
  echo "⚠️  Config/AMC-MobileApp-Info.plist n'a pas ce REVERSED_CLIENT_ID comme schéma d'URL : la connexion Google échouera." >&2
fi
