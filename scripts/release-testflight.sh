#!/usr/bin/env bash
# BBHealth -> TestFlight, trọn gói:
#   ký (profile qua API) -> bump build -> xcodegen -> archive -> export thủ công -> upload -> export compliance.
# Chạy từ bất kỳ đâu:  scripts/release-testflight.sh
# Biến BẮT BUỘC (tài khoản App Store Connect CỦA BẠN — xem docs/RELEASE.md):
#   ASC_KEY_ID, ASC_ISSUER_ID ; file khoá ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 (hoặc ASC_KEY_PATH)
# Team + bundle id lấy từ Config/Local.xcconfig (DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER).
# Biến tuỳ chọn: MARKETING_VERSION=1.1 (đổi version hiển thị) · SKIP_BUMP=1 (giữ số build) ·
#               UPLOAD_WITH=fastlane (mặc định altool) · WAIT_MIN=15 (phút chờ ASC xử lý build) ·
#               ASC_PROFILE_NAME (mặc định BBHealth-AppStore) · BBH_TESTERS="a@x.com,b@y.com"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcvar() {  # đọc NAME = value từ Config/Local.xcconfig (bỏ chú thích //)
  sed -n "s|//.*||; s|^[[:space:]]*$1[[:space:]]*=[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$|\1|p" \
    Config/Local.xcconfig 2>/dev/null | tail -1
}
[[ -f Config/Local.xcconfig ]] || { echo "Thiếu Config/Local.xcconfig — xem docs/SETUP.md"; exit 1; }
KEY_ID="${ASC_KEY_ID:?Đặt ASC_KEY_ID (khoá App Store Connect API của bạn) — xem docs/RELEASE.md}"
ISSUER_ID="${ASC_ISSUER_ID:?Đặt ASC_ISSUER_ID — xem docs/RELEASE.md}"
TEAM_ID="$(xcvar DEVELOPMENT_TEAM)"
BUNDLE="$(xcvar PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$TEAM_ID" && -n "$BUNDLE" ]] || { echo "Config/Local.xcconfig thiếu DEVELOPMENT_TEAM hoặc PRODUCT_BUNDLE_IDENTIFIER"; exit 1; }
PROFILE="${ASC_PROFILE_NAME:-BBHealth-AppStore}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
[[ -f "$KEY_PATH" ]] || { echo "Không thấy file khoá $KEY_PATH"; exit 1; }
export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH="$KEY_PATH"

ARCHIVE="build/BBHealth.xcarchive"
EXPORT_DIR="build/export"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bbhealth-release.XXXXXX")"   # ngoài repo; chứa json key tạm
trap 'rm -rf "$TMP"' EXIT

mkdir -p build
step() { printf '\n==> %s\n' "$*"; }

# 0. App record phải có trước (API không tạo được) -------------------------------------------
step "Kiểm tra app record trên App Store Connect"
if ! APP_ID="$(python3 scripts/asc_testflight.py app-id)"; then
  cat <<MSG
CHƯA có app record cho $BUNDLE trên App Store Connect -> upload sẽ bị từ chối.
Tạo tay (xem docs/RELEASE.md mục "Tạo app record"), rồi chạy lại script.
MSG
  exit 3
fi
echo "App id: $APP_ID"

# 1. Signing: bundleId + HealthKit + profile (giữ profile nếu còn ACTIVE) --------------------
step "Signing qua ASC API"
python3 scripts/asc_signing.py --keep-profile

# 2. Version -----------------------------------------------------------------------------
step "Bump version trong project.yml"
python3 - "$ROOT/project.yml" "${MARKETING_VERSION:-}" "${SKIP_BUMP:-0}" <<'PY'
import re, sys
path, mv, skip = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
s = open(path).read()
m = re.search(r'^(\s*)CURRENT_PROJECT_VERSION:\s*"?(\d+)"?\s*$', s, re.M)
if m:
    n = int(m.group(2)) + (0 if skip else 1)
    s = s[:m.start()] + f'{m.group(1)}CURRENT_PROJECT_VERSION: "{n}"' + s[m.end():]
else:
    n = 1
    s = s.replace("  base:\n", f'  base:\n    CURRENT_PROJECT_VERSION: "{n}"\n', 1)
mm = re.search(r'^(\s*)MARKETING_VERSION:\s*"?([^"\n]+)"?\s*$', s, re.M)
if mm:
    ver = mv or mm.group(2).strip()
    s = s[:mm.start()] + f'{mm.group(1)}MARKETING_VERSION: "{ver}"' + s[mm.end():]
else:
    ver = mv or "1.0"
    s = s.replace("  base:\n", f'  base:\n    MARKETING_VERSION: "{ver}"\n', 1)
open(path, "w").write(s)
open(sys.argv[1] + ".release-version", "w").write(f"{ver} {n}\n")
print(f"MARKETING_VERSION={ver} CURRENT_PROJECT_VERSION={n}")
PY
read -r VERSION BUILD < "$ROOT/project.yml.release-version"; rm -f "$ROOT/project.yml.release-version"

# 3. Generate + archive ------------------------------------------------------------------
step "xcodegen generate"
xcodegen generate

step "Archive $VERSION ($BUILD)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
  -project BBHealth.xcodeproj -scheme BBHealth -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE" | tee build/archive.log | grep -E '^(\*\*|error:|warning: .*sign)' || true
[[ -d "$ARCHIVE" ]] || { echo "Archive thất bại — xem build/archive.log"; exit 1; }

# 4. Export thủ công (key không có cloud-signing -> không dùng automatic) ---------------------
step "Export IPA (manual, $PROFILE)"
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict><key>$BUNDLE</key><string>$PROFILE</string></dict>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
# `/usr/bin` lên đầu PATH: bước tạo IPA của xcodebuild gọi rsync và spawn 1 tiến trình
# "remote" (localhost) cũng bằng rsync tìm trong PATH. Nếu PATH ưu tiên rsync Homebrew (3.4.x)
# nó không nhận cờ `--extended-attributes` mà openrsync (/usr/bin/rsync) của Apple gửi -> "Copy failed".
# Ép cả 2 đầu dùng /usr/bin/rsync để export chạy được.
PATH="/usr/bin:$PATH" xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions.plist | tee build/export.log | grep -E '^(\*\*|error:)' || true
IPA="$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1)"
[[ -n "$IPA" ]] || { echo "Export thất bại — xem build/export.log"; exit 1; }
echo "IPA: $IPA"

# 5. Upload ------------------------------------------------------------------------------
step "Upload TestFlight"
upload_fastlane() {
  python3 - "$KEY_PATH" "$TMP/asc_key.json" "$KEY_ID" "$ISSUER_ID" <<'PY'
import json, sys
json.dump({"key_id": sys.argv[3], "issuer_id": sys.argv[4], "key": open(sys.argv[1]).read(),
           "in_house": False}, open(sys.argv[2], "w"))
PY
  chmod 600 "$TMP/asc_key.json"
  fastlane run upload_to_testflight ipa:"$IPA" api_key_path:"$TMP/asc_key.json" \
    skip_waiting_for_build_processing:true
}
if [[ "${UPLOAD_WITH:-altool}" == "fastlane" ]]; then
  upload_fastlane
else
  xcrun altool --upload-app -f "$IPA" -t ios \
    --api-key "$KEY_ID" --api-issuer "$ISSUER_ID" --p8-file-path "$KEY_PATH" \
    || { echo "altool lỗi -> thử fastlane"; upload_fastlane; }
fi

# 6. Chờ ASC xử lý -> export compliance + nhóm TestFlight nội bộ --------------------------
step "Chờ build xử lý + export compliance"
python3 scripts/asc_testflight.py finalize "$BUILD" "${WAIT_MIN:-15}" || \
  echo "(chưa xong — chạy lại sau: python3 scripts/asc_testflight.py finalize $BUILD)"

printf '\nBBHealth %s (build %s) đã upload. Nhớ commit project.yml (bump version).\n' "$VERSION" "$BUILD"
