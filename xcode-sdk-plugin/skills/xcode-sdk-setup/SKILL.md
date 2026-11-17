---
name: xcode-sdk-setup
description: 把 SDK 目录（AppSDK / TWSDK 等）一键接入 Cocos Creator 或 Unity 导出的 iOS Xcode 工程：导入 framework/bundle/源码、build settings、Bundle ID、Info.plist、图标、启动图、entitlements、最低 iOS 版本。用户说"接入 SDK""配置 Xcode 工程""重新导出 iOS 工程后配 SDK"时使用。
---

# Xcode SDK 接入（Cocos / Unity iOS 工程）

本 skill 自带脚本 `scripts/update_build_settings_asset.rb`（下称「脚本」），用它把 SDK 目录一次性配进 Xcode 工程。**不要自己重写脚本，也不要改用工程里其他版本**，除非用户明确要求。

## Codex 专用 agent 交接

用户要求独立 agent 执行时，主 agent 使用已注册的 `xcode_sdk_setup`，不要只在主会话执行后称已委派。若尚未注册，读取同包的 `../xcode-sdk-agent-setup/SKILL.md`，按其流程安装专用 agent，并提示新建对话；当前客户端没有子 agent 能力时明确说明限制。

主 agent 先按第 1 步补齐参数，并告知可选资源的影响，再委派。交接包括：工程和 SDK 的绝对路径、iOS App target、最低 iOS 版本、Team ID 及来源、图标/启动图/entitlements 处理范围、是否编译，以及当前 Skill 的实际路径。运行期间由主 agent 处理子 agent 返回的缺失参数或授权需求，补齐后继续同一个执行任务。等待子 agent 完成，再向用户汇总；同一工程不要由多个 agent 同时修改。

子 agent 直接按下面流程执行，不再次委派。普通 Skill 调用仍可由主 agent 完成。

## 运行环境

- 必须在 **macOS** 上运行（依赖系统自带的 `plutil` 和 `sips`），需要 Ruby。
- 首次运行会自动安装 `xcodeproj` gem（普通安装 → sudo → --user-install），可能需要用户输入密码。
- 当前环境不是 Mac（Linux、云端容器）时：不要尝试运行。按下面步骤确认好参数，把完整命令交给用户在 Mac 终端执行，再让用户贴回输出。

## 第 1 步：确认参数

优先从用户提供的信息和工程里查出下面几项，已能确定的参数不用重复询问。缺失的关键参数向用户询问；如果由独立子 agent 执行且无法提问，返回缺失项给调用方，补全后再运行。

iOS App target 有多个候选且无法确定时，列出候选并等待选择，不要猜。最低 iOS 版本优先沿用工程现有值；多个 target 的版本不一致时，先说明脚本会统一版本并确定本次使用值。

| 参数 | 说明 | 怎么查 |
|---|---|---|
| 工程路径 | `.xcodeproj` 的路径。Cocos 3.x 通常在 `build/ios/proj/`，Cocos 2.x 在 `build/jsb-default/frameworks/runtime-src/proj.ios_mac/`，Unity 在导出目录根部 | `find . -name "*.xcodeproj" -maxdepth 6` |
| iOS 主 target | 必须是 iPhone App target。Cocos 2.x 常见 `<项目名>-mobile`（不要选 `-desktop`），Unity 是 `Unity-iPhone`，Cocos 3.x 是项目名 | `awk '/Begin PBXNativeTarget/,/End PBXNativeTarget/' <工程>/project.pbxproj \| grep -E 'name =\|productType'`，选 `productType = "com.apple.product-type.application"` 的 |
| SDK 目录 | 含 `AppSDK.framework`、`Info.plist` 等的目录，例如 `native/engine/ios/SDK` | 问用户；或 `grep -oE 'path = [^;]*SDK[^;]*' project.pbxproj \| sort -u` 看工程现在引用的 |
| 最低 iOS 版本 | 不传时脚本会把**所有** iOS target 改成默认 13.0 | `grep -o 'IPHONEOS_DEPLOYMENT_TARGET = [^;]*' project.pbxproj \| sort \| uniq -c`，沿用现有值 |
| Team ID | 签名用的开发者团队 ID | 看 SDK `Info.plist` 有没有 `teamid` 键 |

**Team ID 很重要**：SDK 的 `Info.plist` 里没有 `teamid` 时，脚本会用内置的默认 Team ID，这多半不是用户自己的团队。这种情况优先用用户或调用方明确提供的 Team ID；仍没有时不要运行脚本，先询问或向调用方返回缺失项。运行时加上 `--set DEVELOPMENT_TEAM=<TeamID>`。

再检查 SDK 目录里有哪些可选文件，提前告诉用户会发生什么：

- `1024.png`：会生成 AppIcon，并**删除工程里自带的 `Images.xcassets`（包括磁盘上的文件夹）**。
- `LaunchScreen.storyboard`（及 `LaunchScreenBackground.png`）：会替换启动图。
- `sdk.entitlements`：会设置 `CODE_SIGN_ENTITLEMENTS`；没有则保留原值。

## 第 2 步：运行

**必须在 `.xcodeproj` 所在目录执行，并显式传工程名和 target 名**（脚本在 skill 目录里，自动查找工程会找不到）。`<SKILL_DIR>` 是当前已加载的 `SKILL.md` 所在目录的绝对路径。Claude 和 Codex 都以实际安装位置为准，不要硬编码本仓库路径，也不要依赖插件专属环境变量。路径含空格时用引号包裹。

```bash
cd "<xcodeproj 所在目录>"
ruby "<SKILL_DIR>/scripts/update_build_settings_asset.rb" "<工程>.xcodeproj" "<target>" \
  --add-dir "<SDK目录，相对当前目录>" --ios-min <版本> [--set DEVELOPMENT_TEAM=<TeamID>]
```

示例：

- Cocos 3.x：`ruby <SKILL_DIR>/scripts/update_build_settings_asset.rb NewProject.xcodeproj NewProject --add-dir ../../../native/engine/ios/SDK --ios-min 15.0`
- Cocos 2.x（同时把 hortor 资源目录加成蓝色文件夹）：`ruby <SKILL_DIR>/scripts/update_build_settings_asset.rb MyGame.xcodeproj MyGame-mobile --add-dir <SDK目录> --Asset`
- Unity：`ruby <SKILL_DIR>/scripts/update_build_settings_asset.rb Unity-iPhone.xcodeproj Unity-iPhone --add-dir <SDK目录>`

脚本会先把整个 `.xcodeproj`（以及被修改的子工程）备份成 `<工程>.xcodeproj.bak-<时间戳>`，不用手动备份。

### 其他选项

| 选项 | 作用 |
|---|---|
| `--set KEY=VALUE` | 设置字符串 build setting，**覆盖**原值，可重复 |
| `--set-array KEY=v1,v2` | 设置数组 build setting，**覆盖**，要保留原值自己写 `$(inherited)` |
| `--append KEY=v1,v2` | **追加**值、保留原值，如 `OTHER_LDFLAGS=-ObjC,-lz` |
| `--ios-min 15.0` | 最低 iOS 版本，作用于所有 iOS target 和子工程（如 `cocos2d_libs.xcodeproj`），不动 macOS target |
| `--include-project` | 项目级 build settings 也一起改 |
| `--Asset` | Cocos 2.x：把 `jsb-adapter/assets/src/hortor` 旁边的资源目录加成蓝色文件夹，并清理旧的 Copy Files 阶段 |

## 脚本会做什么

对选中的主 target 写入：`ENABLE_BITCODE=NO`、`TARGETED_DEVICE_FAMILY=1,2`、`CODE_SIGN_STYLE=Automatic`、`CODE_SIGN_IDENTITY=Apple Development`、`LD_RUNPATH_SEARCH_PATHS`、`FRAMEWORK_SEARCH_PATHS=$(SRCROOT)/<SDK目录>`、`DEVELOPMENT_TEAM` 等，然后：

1. 删掉工程里指向该 SDK 目录的旧引用，再递归重新导入：`.framework` 链接并 Embed & Sign，`.bundle` 进 Resources，源文件进编译，头文件只加引用；跳过 `Info.plist`、`.DS_Store`、`.dSYM`。
2. `INFOPLIST_FILE` 指向 SDK 目录的 `Info.plist`；`PRODUCT_BUNDLE_IDENTIFIER` 取其中的 `CFBundleIdentifier` / `bundleid`。
3. 处理图标、启动图、entitlements（见第 1 步）。
4. 非 Unity 工程把 `SDKMessager.mm` 加入主 target。
   另外，给引擎 target（Cocos 3.x 的 `cocos_engine`、Cocos 2.x 的 `libcocos2d iOS`，包括子工程里的）的 `OTHER_CPLUSPLUSFLAGS` 追加 `-Wno-invalid-specialization`，解决 Xcode 27 新版 clang 下引擎 `half.h` 报 `'is_floating_point' cannot be specialized` 的问题。输出里对应 `Appended OTHER_CPLUSPLUSFLAGS ... to engine targets` 一行。
5. Unity 工程：`AppSDK.framework` 和 `SDKMessager.mm` 挂到 `UnityFramework`，同步它的搜索路径和最低版本；主 target 对 AppSDK 做 Embed & Sign；`Unity-iPhone` 链接 `UnityFramework.framework`。

脚本**不会**修改启动文件（`AppDelegate.mm` / `AppController.mm` / `UnityAppController.mm`），也不需要用户在启动文件里写 AppSDK 初始化代码，不要提醒用户检查或添加初始化代码。

## 第 3 步：核对输出并向用户总结

出现 `Error:` 就停下来报告原因。否则总结：

- 备份路径和回滚命令（输出里的 `Backup:` 和 `To undo:`）；
- 实际使用的 target，确认是 iOS 主 target；
- 最低 iOS 版本，以及应用到的 target 和子工程；
- 导入、挂载的文件数（`Imported references`、`Package references attached`）；
- Bundle ID、INFOPLIST_FILE、DEVELOPMENT_TEAM 来源（plist 的 teamid 还是 --set）；
- 图标是否生成、`Images.xcassets` 是否被删、启动图是否替换；
- `SDKMessager.mm` 挂到了哪个 target；CODE_SIGN_ENTITLEMENTS 是设置还是跳过；
- Unity：AppSDK link/embed 状态、UnityFramework 链接状态。

最后提醒用户：

1. 命令行编译关闭了签名，在 Xcode 里真机运行前先 Clean Build Folder（Shift+Cmd+K）；
2. 在 General → Minimum Deployments 抽查版本，在 Signing & Capabilities 确认团队；
3. Cocos / Unity 每次重新导出 iOS 工程都会覆盖 `project.pbxproj`，需要再跑一次本 skill。

## 第 4 步：编译验证，出错时尝试修复

第 3 步没有 `Error:` 时，读取 `references/build-and-fix.md`，按里面的命令编译主 target。编译失败就按其中的规则修复：只改工程配置，最多 5 轮；需要改源代码、签名或 SDK 文件时停下来汇报。用户明确说不需要编译时跳过本步。

当前环境不是 Mac 时跳过本步，把编译命令交给用户执行，再根据用户贴回的错误按同样的规则给出修复建议。

## 常见问题

- **选错 target（如 Mac target）**：用备份回滚（`To undo:` 那行命令）或 `git checkout`，再用正确 target 重跑。
- **签名报错 / 团队不对**：用 `--set DEVELOPMENT_TEAM=<TeamID>` 重跑，或在 SDK Info.plist 加 `teamid`。
- **xcodeproj gem 装不上**：让用户手动执行 `sudo gem install xcodeproj`，或用 rbenv / Homebrew 的 Ruby 运行。
- **Xcode 27 / iOS 27 SDK 报 "UIScene life cycle is required"**：需要把启动代码改成 UIScene 生命周期并用 `UIWindow initWithWindowScene:` 创建窗口，脚本不处理这一项。
- **备份目录越来越多**：`*.xcodeproj.bak-*` 可以在确认工程正常后删除。
