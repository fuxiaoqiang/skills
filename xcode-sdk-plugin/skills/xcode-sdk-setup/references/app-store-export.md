# 本地导出 App Store IPA（不上传）

仅用户明确要求“导出 IPA”“打 App Store 包”“归档用于上架”时执行；普通 SDK 接入不自动归档。也可对已接入的工程单独执行，不强制重新接入 SDK。流程使用 Xcode 自带工具，不需要 Ruby、Fastlane 或第三方打包脚本。

## 1. 参数和签名前提

- 读取用户提供或本工程已确定的 SDK 根目录 `Info.plist` 的 `teamid`（用 plutil 读取，不修改 SDK）。缺失时向用户请求 Team ID，不使用默认团队。该值决定本次 DEVELOPMENT_TEAM 和导出 teamID。
- 如 plist teamid、工程、现有 archive 或用户明确指定的团队冲突，先报告冲突并确定使用值，不静默切换团队或修改供应商文件。
- 确定主 App target 与可归档 scheme；支持 Cocos、Unity-iPhone / UnityFramework 和 Tuanjie-iPhone / TuanjieFramework。使用关联 workspace（如存在 CocoaPods），用 xcodebuild -list 核对，不能归档 Tests、GameAssembly 或引擎 framework 来替代 App。
- 确定输出目录，默认工程旁的 `AppStoreExport/<时间戳>/`，使用新目录，包含 archive、ExportOptions.plist、export 目录、日志。不覆盖已有包。保持 CFBundleShortVersionString / CFBundleVersion 现值，报告缺失或无效值，不自动增加版本号。
- Team ID 本身不提供签名能力。检查本机已登录的 Xcode 开发者账户、可用签名身份、私钥及对应团队的 App Store 描述文件 / 自动签名权限。可用 `security find-identity -v -p codesigning` 查看身份，但不输出私钥或账号凭据。
- 结合 `xcodebuild -showBuildSettings` 检查 Release 下 Bundle ID、签名方式、entitlements、配置文件指定及各 App extension 的团队。需匹配 App Store 分发，不使用 development、ad-hoc、enterprise、仅内部 TestFlight 的导出包冒充 App Store 包。
- 自动签名已有条件足够则直接继续；如需 Xcode 联网获取/创建证书、描述文件或注册 App ID，先向用户说明需要的具体操作。只有授权后添加 `-allowProvisioningUpdates`；这不等于上传 App，但可能修改开发者账户签名资源。不要更改钥匙串、创建证书、获取密钥或要求 Apple 密码作为无条件自动修复步骤。
- 手动签名保留既有方式，确认 App 及 extension 的 distribution profile 和证书映射；缺失则停止报告，不能改成自动签名掩盖问题。

## 2. Archive：必须开启签名

先执行本 Skill 的静态检查；用户同时要求接入时先完成接入再归档。归档与关闭签名的编译验证不同：不复用 `CODE_SIGNING_ALLOWED=NO` / `CODE_SIGNING_REQUIRED=NO`，不把无签名产物直接压缩成 IPA。

以下为命令模板，替换实际路径、团队和 scheme；project / workspace 二选一，不顺序重复执行。

```bash
xcodebuild -workspace "<工程>.xcworkspace" -scheme "<主App scheme>" \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "<输出目录>/App.xcarchive" \
  DEVELOPMENT_TEAM="<Info.plist中的teamid>" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES archive \
  > "<输出目录>/archive.log" 2>&1
sdk_archive_status=$?
printf 'archive exit=%s\n' "$sdk_archive_status"
```

无 workspace 时将 `-workspace` 换成 `-project "<工程>.xcodeproj"`。scheme 的 Archive 配置明确为非 Release 的自定义发布配置时使用确认的实际配置，不擅自改变 scheme。

- 保留用户签名方式，归档可按 Xcode 自动签名使用开发身份，再于 export 重签为 distribution；不能据 archive 身份名称单独断定导出失败。
- 确认 archive Info.plist 有主 App 的 ApplicationProperties，且 Products/Applications 下存在实际主 App。Unity / 团结引擎产品通常需要 SKIP_INSTALL=YES、主 App=NO 才能生成 App archive；仅在 archive 结构证明配置错误时，备份并局部修复相应 Release 配置，不将该值全局覆盖到所有 target。
- 归档失败时保留日志，不继续导出。工程配置错误按 build-and-fix.md 最多 5 轮修复；签名、证书、profile、账户权限错误停止报告，不修改源码或 SDK。

## 3. ExportOptions 和导出

先读取当前 `xcodebuild -help` 的导出选项。支持时 method 使用 `app-store-connect`；旧版 Xcode 仅支持旧名称时用 `app-store`。两者均要求 `destination=export`，绝不能设 upload。

自动签名示例（按实际 Team ID 生成 XML plist 并 plutil -lint）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>TEAM_ID_FROM_SDK_PLIST</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><false/>
</dict></plist>
```

- 手动签名改为 signingStyle=manual，signingCertificate 使用已确定的 Apple Distribution 身份 / SHA-1；provisioningProfiles 字典必须包含每个可执行 App / extension 的 Bundle ID → profile 名称或 UUID，不为纯 framework 填 profile。
- 不启用 testFlightInternalTestingOnly。保持本地导出；uploadSymbols=false 不替代 destination 检查，保留 archive 内 dSYM 供用户后续使用。
- ExportOptions.plist 用实际值，不能留下 TEAM_ID_FROM_SDK_PLIST 之类占位符。

```bash
xcodebuild -exportArchive -archivePath "<输出目录>/App.xcarchive" \
  -exportOptionsPlist "<输出目录>/ExportOptions.plist" \
  -exportPath "<输出目录>/export" \
  > "<输出目录>/export.log" 2>&1
sdk_export_status=$?
printf 'export exit=%s\n' "$sdk_export_status"
```

不要调用上传命令、Transporter、altool 上传、App Store Connect 上传 API 或添加上传 post-action。归档前检查 scheme 的 Archive pre/post action 和构建脚本；如有自动上传行为，停止指出并让用户确定如何禁用，不能执行已知会上传的流程。

## 4. 本地验证和交付

- 检查退出码及实际生成的 .ipa，归档成功不等于导出成功。失败时报告真实阶段和日志，不将旧 IPA 当成本次产物。
- 对本次 IPA 用 `unzip -t` 检查，并解压到临时目录，确认 Payload 下主 .app、Bundle ID、版本、build 号。
- `codesign --verify --deep --strict --verbose=2 "<App路径>"` 检查签名；`codesign -d --entitlements :- "<App路径>"` 检查实际 team / application-identifier 和 get-task-allow=false。
- 如含 embedded.mobileprovision，用 `security cms -D -i` 解码，核对 TeamIdentifier、App ID、有效期、App Store 分发属性；对 extension 同样检查。不能包含 development 设备列表或 enterprise 的 ProvisionsAllDevices=true。没有本地 profile 但当前 Xcode 分发机制允许时记录实际证据，不凭空判定通过。
- 核对所有动态 framework 已正确嵌入签名，主 App 不包含静态 framework 的错误嵌入。
- 返回 IPA、xcarchive、dSYM、ExportOptions.plist、归档/导出日志的绝对路径，包含使用的 teamid 来源、scheme、Bundle ID、版本/build、签名方式和验证结果。
- 明确“已本地导出，未上传”；本地检查不等于 Apple 服务端处理、验证或审核通过，不承诺必定被 App Store 接受。缺签名条件则报告阻塞项，不交付无签名伪上架包。

参考：Apple [命令行归档和导出](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)、[归档导出文件](https://help.apple.com/xcode/mac/current/en.lproj/deva1f2ab5a2.html)。具体选项以用户当前 Xcode 的 xcodebuild -help 为准。
