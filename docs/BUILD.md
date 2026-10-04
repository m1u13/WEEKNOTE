# ビルドとiPhoneへのインストール

WEEKNOTEはSwiftUIで実装したiOSアプリです。対応OSはiOS 17以降、アプリIDは `com.m1u13.weeknote` です。Xcodeプロジェクトは `project.yml` からXcodeGenで生成します。生成された `WEEKNOTE.xcodeproj` はGit管理に含めません。

## GitHub Actionsで生成するファイル

`iOS build and tests` はmainへのpush、Pull Request、手動実行で動きます。macOS 15とXcode 16.4を指定し、次の処理を実行します。

- iPhone 16とiPhone SE（第3世代）、iOS 18.5でユニットテストとUIテストを実行。
- ライト・ダーク表示のスクリーンショット、UIテストの画面添付、実行ログ、`.xcresult` を保存。
- シミュレーター用の `.app` をZIP形式で保存。
- 実機向けReleaseビルドを `WEEKNOTE-unsigned.ipa` にまとめ、内容とSHA-256を確認。

GitHubリポジトリの **Actions → 実行結果 → Artifacts** からダウンロードできます。通常の成果物は30日、実機ビルドログは14日保存します。

**`WEEKNOTE-unsigned.ipa` は未署名です。このファイルをそのまま通常のiPhoneにインストールすることはできません。** 実機利用にはAppleの証明書とプロビジョニングプロファイルによる署名が必要です。シミュレーター版はMac上のiOS Simulatorで動作します。

GitHubの[macOS 15ランナー一覧](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)で、Xcode 16.4、Xcode 26.3、使用するシミュレーターの提供を確認しています。ランナー更新で指定バージョンが提供されなくなった場合は、ワークフローの `DEVELOPER_DIR` と `SIMULATOR_RUNTIME` を一覧に合わせて更新してください。

## Macで開く

XcodeとXcodeGenが必要です。

```bash
brew install xcodegen
bash scripts/generate-project.sh
open WEEKNOTE.xcodeproj
```

XcodeでWEEKNOTEスキームとiPhone Simulatorを選択して実行します。実機では、WEEKNOTEターゲットの **Signing & Capabilities → Team** で自分の開発チームを設定します。XcodeがアプリIDの利用を拒否した場合は、`project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を自分の管理するIDに変更し、プロジェクトを再生成してください。CIの署名用プロファイルと検証スクリプトも同じIDに合わせる必要があります。

CIと同じテストをMacで実行する例です。指定したシミュレーターランタイムがインストールされている必要があります。

```bash
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
SIMULATOR_NAME="iPhone 16" SIMULATOR_RUNTIME=iOS-18-5 bash scripts/ci-test.sh
```

テスト成果物は `build/` に作成します。同じ場所に既存の `.xcresult` がある場合は別の保存先に退避してから実行してください。`--uitesting` 起動時はサンプルデータを入れたテスト用保存先を使用します。

シミュレーター版のZIPを展開した後は、次のようにインストールできます。

```bash
xcrun simctl install booted /path/to/WEEKNOTE.app
xcrun simctl launch booted com.m1u13.weeknote
```

## 署名済みIPAを生成する

`Signed iOS IPA` は **mainブランチで手動実行** します。自動でApp Store Connectへアップロードする処理は含めていません。Xcode 26.3でアーカイブし、指定した配布方法に合わせて署名済みIPAを出力します。

2026年4月28日以降、App Store ConnectへのアップロードにはXcode 26以降とiOS 26 SDK以降が必要です。通常の未署名ビルドで使うXcode 16.4と、ストア提出用の署名ワークフローのXcodeを分けています。[AppleのSDK要件](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)

リポジトリの **Settings → Secrets and variables → Actions → New repository secret** に以下を登録します。証明書、秘密鍵、プロファイルはソースコードに保存しないでください。

| Secret名 | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | 秘密鍵を含む署名証明書 `.p12` をBase64化した文字列 |
| `P12_PASSWORD` | `.p12` エクスポート時に指定したパスワード。パスワード付きのファイルを使用 |
| `BUILD_PROVISION_PROFILE_BASE64` | WEEKNOTE用 `.mobileprovision` をBase64化した文字列 |
| `KEYCHAIN_PASSWORD` | CIが作成する一時キーチェーン用の任意の強いパスワード |
| `APPLE_TEAM_ID` | 証明書とプロファイルを所有するApple DeveloperチームID |

MacでBase64をクリップボードにコピーする例です。ファイル名は手元の実際のファイルに置き換えてください。

```bash
base64 -i WEEKNOTE-signing.p12 | pbcopy
base64 -i WEEKNOTE.mobileprovision | pbcopy
```

証明書とプロファイルの準備・登録方法は[GitHubの公式手順](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)も参照できます。

配布方法は実行画面の `export_method` で選びます。

| 値 | 証明書とプロファイル | 用途 |
| --- | --- | --- |
| `release-testing` | Apple Distribution証明書とAd Hocプロファイル | 事前登録したiPhoneで使う配布用IPA。使用する端末のUDIDをプロファイルに含める |
| `debugging` | Apple Development証明書とiOS App Developmentプロファイル | 登録済み実機での開発・デバッグ |
| `app-store-connect` | Apple Distribution証明書とApp Storeプロファイル | TestFlight・App Store提出用IPA。別途App Store Connectへのアップロードが必要 |

プロファイルのApp IDは **`com.m1u13.weeknote` を明示的に指定したもの** を使用します。ワークフローは有効期限、チーム、アプリID、証明書と秘密鍵の組み合わせ、配布方法とプロファイル種別を確認してからアーカイブします。Ad HocとTestFlightの配布はApple Developer Programのチームで行います。[Appleの登録済みデバイスへの配布手順](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)、[ベータ版・リリース版の配布手順](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)

成功すると `WEEKNOTE-signed-配布方法` のArtifactにIPAとチェックサムが保存されます。署名済み成果物の保存期間は14日です。証明書・プロファイル・一時キーチェーンは実行終了時に削除します。

Ad Hoc/開発用IPAは、プロファイルに登録したiPhoneにXcodeの **Window → Devices and Simulators** からインストールできます。App Store用IPAはTestFlightやApp Store配布の処理を経てインストールします。

## リソースと保存データ

- 本文と日本語表示はシステムフォントを使用します。見出し用のAntonは `WEEKNOTE/Resources/Fonts/Anton-Regular.ttf` に同梱し、`Info.plist` の `UIAppFonts` で登録しています。XcodeGenの通常のリソースコピーではファイルがアプリバンドル直下に置かれるため、登録値はファイル名のみです。フォントのライセンスは同じフォルダの `OFL.txt` に保存しています。
- タスク・予定・習慣の記録は端末内に保存します。JSONバックアップはアプリの設定から書き出し・読み込みを行います。Web版のブラウザー保存データとは保存先が異なります。
- `PrivacyInfo.xcprivacy` では追跡・収集データなしと、アプリ自身の設定を保存するUserDefaultsの利用理由を宣言しています。外部送信やSDKを追加する際は、実際の機能に合わせて更新してください。[Appleのプライバシーマニフェスト](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)

