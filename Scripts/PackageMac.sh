#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_path="$project_root/build/distribution"
output_path="$project_root/dist/CouchRemote-macOS13-universal.dmg"
staging_path="$(mktemp -d "${TMPDIR:-/tmp}/couchremote-package.XXXXXX")"
trap 'rm -rf "$staging_path"' EXIT

# Ad-hoc by default; Developer ID release signing is explicit.
signing_identity="${SIGNING_IDENTITY:--}"
signing_flags=(CODE_SIGN_STYLE=Manual)
if [[ "$signing_identity" != "-" ]]; then
    [[ "$signing_identity" == "Developer ID Application:"* ]] || { echo 'Use a Developer ID Application identity.' >&2; exit 1; }
    signing_flags+=(ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp)
fi
xcodebuild -quiet -project "$project_root/CouchRemote.xcodeproj" \
    -scheme CouchRemoteMac -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$build_path" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="$signing_identity" "${signing_flags[@]}" build

app_path="$build_path/Build/Products/Release/CouchRemoteMac.app"
codesign --verify --strict "$app_path"
architectures="$(lipo -archs "$app_path/Contents/MacOS/CouchRemoteMac")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]]
ditto "$app_path" "$staging_path/CouchRemoteMac.app"
ln -s /Applications "$staging_path/Applications"
cat > "$staging_path/설치 안내.txt" <<'EOF'
Couch Remote — Mac

지원: macOS 13 Ventura 이상, Intel 또는 Apple Silicon Mac.
Bluetooth LE 주변 기기 모드를 지원하는 Mac이 필요합니다.
다른 Mac 모델에서의 실제 Bluetooth 동작은 아직 검증하지 않았습니다.

1. CouchRemoteMac 앱을 Applications 폴더로 드래그하세요.
2. Applications에서 앱을 여세요. Xcode는 필요 없습니다.
3. Bluetooth 접근을 허용하세요.
4. 앱의 Grant Accessibility access 버튼을 누르고,
   시스템 설정의 개인정보 보호 및 보안에서 앱의 손쉬운 사용 권한을 켜세요.
5. iPhone의 Couch Remote 앱에서 Mac을 선택하고 두 기기의 코드를 확인하세요.

개인 테스트용 빌드는 Apple의 배포 공증을 받지 않아
처음 실행할 때 macOS가 차단할 수 있습니다. 본인이 전달받은 파일인지
확인한 뒤 Apple의 공식 안내를 참고하세요:
https://support.apple.com/102445

이 설치 파일에는 Mac 앱만 들어 있습니다.
iPhone 앱은 별도 설치가 필요하며, 무료 개발 계정 설치는 주기적으로 갱신해야 합니다.
EOF

mkdir -p "$project_root/dist"
hdiutil create -ov -volname 'Couch Remote' -srcfolder "$staging_path" \
    -format UDZO "$output_path"
hdiutil verify "$output_path"
printf '\nCreated: %s\n' "$output_path"
