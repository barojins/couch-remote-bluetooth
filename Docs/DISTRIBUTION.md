# Apple Developer Program 배포

소스만으로 멤버십 가입, 인증서 발급, App Review 승인이 완료되지는 않습니다. 결제·약관 동의는 계정 소유자가 직접 진행합니다. 인증서 개인 키, 비밀번호, 프로비저닝 파일은 GitHub에 올리지 마세요.

## iPhone: TestFlight → App Store

1. 유료 Apple Developer Program에 가입하고 Xcode Settings → Accounts에 해당 계정을 추가합니다.
2. `Config/Local.xcconfig.example`을 `Config/Local.xcconfig`로 복사하고 Team ID와 고유 bundle prefix를 입력합니다. 이 파일은 Git에서 제외됩니다.
3. App Store Connect에 `<prefix>.phone`과 일치하는 iOS 앱 레코드를 만듭니다. 표시 이름: Couch Remote. 버전은 1.0.0이며 업로드마다 빌드 번호를 증가시킵니다.
4. 터미널에서 `APPLE_TEAM_ID=YOUR_TEAM BUNDLE_PREFIX=com.yourname.couchremote BUILD_NUMBER=1 bash Scripts/ArchivePhone.sh`를 실행합니다. 또는 Xcode의 CouchRemotePhone scheme에서 Any iOS Device → Product → Archive를 선택합니다.
5. Xcode Organizer에서 Validate App, Distribute App → App Store Connect를 진행합니다. 현재 Apple이 업로드를 허용하는 정식 Xcode를 사용하세요. 로컬 테스트에 쓴 베타 Xcode의 업로드 허용 여부는 별도입니다.
6. TestFlight 테스트 정보, 연락처, 심사용 Bluetooth 테스트 방법을 입력합니다. 외부 테스터 배포는 Apple의 베타 심사가 필요할 수 있습니다. 승인 후 초대 링크로 iPhone에 설치할 수 있습니다. TestFlight 빌드는 최대 90일 동안 유효합니다.
7. 장기 공개 배포는 스크린샷, 개인정보 처리방침 URL, 지원 URL, 연령 등급, 수출 규정 답변 등을 준비해 App Store 심사를 받습니다. 앱은 데이터를 수집하거나 외부 서버로 전송하지 않지만, App Privacy와 암호화 관련 답변은 배포자가 실제 동작과 Apple 규정에 맞게 작성해야 합니다.

### 심사용 동작 설명

이 앱은 macOS 13 이상에서 실행하는 별도의 CouchRemoteMac 수신 앱이 필요합니다. iOS 17 이상 실기기에서 Bluetooth를 켜고 Mac을 선택합니다. 운영체제 Bluetooth 코드를 확인해 페어링한 뒤 앱의 연결 코드를 양쪽 화면에서 확인하고 Mac에서 Trust this iPhone을 선택합니다. 이후 승인된 iPhone은 자동 재연결됩니다. Mac의 Bluetooth 및 Accessibility 권한이 필요합니다. 한 손가락 이동/탭/더블탭, 두 손가락 우클릭/스크롤, 키보드 전송을 지원합니다. Mac companion 다운로드 URL과 설치 안내를 심사 정보에 제공하세요. Apple 심사 승인 여부는 보장되지 않습니다.

## Mac: Developer ID 서명 + 공증 DMG

1. Xcode에서 **Developer ID Application** 인증서를 발급받습니다. Apple Development 인증서는 배포 공증용이 아닙니다.
2. Apple 공식 notarytool 안내에 따라 Keychain credential profile을 만듭니다. 비밀번호를 파일이나 저장소에 저장하지 마세요.
3. `DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' NOTARY_PROFILE=couch-remote bash Scripts/NotarizeMac.sh`를 실행합니다.
4. 공증 제출이 Accepted가 되고 stapler 검증까지 성공한 `dist/CouchRemote-macOS13-universal.dmg`만 사용자에게 배포합니다. 스크립트가 실패한 파일을 공증 완료로 표시하지 마세요.
5. GitHub Releases에 이 DMG를 첨부할 수 있습니다. 이 저장소는 비공개이므로 접근 권한이 없는 사용자는 다운로드할 수 없습니다.

최종 사용자는 Xcode 없이 DMG에서 Applications로 드래그해 설치합니다. 새 Mac마다 Bluetooth 및 Accessibility 권한 승인은 여전히 필요합니다. macOS 13 이상 / Intel 및 Apple Silicon 빌드이며, 다른 모델의 Bluetooth LE peripheral 지원과 동작은 실제 기기로 확인해야 합니다.

## 개인정보 및 검증

명령·입력 텍스트는 저장하거나 로그로 남기지 않습니다. 링크 암호화와 최초 신뢰 승인, 입력 권한 확인은 유지됩니다. 승인한 iPhone의 Core Bluetooth 식별자는 Mac에 저장되며 Forget으로 철회할 수 있습니다. iPhone에는 마지막으로 승인받은 Mac의 식별자와 이름을 저장합니다. 자동 테스트는 패킷/페어링 상태/이동 변환을 검증하며 실제 Bluetooth, 제스처 느낌, 다른 Mac 호환성이나 App Review를 대체하지 않습니다.

공식 문서: [멤버십](https://developer.apple.com/support/compare-memberships/), [TestFlight](https://developer.apple.com/testflight/), [Developer ID](https://developer.apple.com/developer-id/), [공증](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
