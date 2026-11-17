---
name: xcode-sdk-setup
description: 把 SDK 目录（AppSDK / TWSDK 等）接入 Cocos Creator 或 Unity 导出的 iOS Xcode 工程，由 agent 直接编辑工程、生成 AppIcon 并编译验证，无需 Ruby 或 xcodeproj gem。用户说“接入 SDK”“配置 Xcode 工程”“重新导出 iOS 工程后配 SDK”时使用。
---

# Xcode SDK 接入（agent 直接执行）

读取工程后直接编辑工程配置和资源，使用 macOS / Xcode 自带工具；不依赖 Ruby、gem、CocoaPods、第三方工程解析库或旧接入脚本。可用宿主提供的文件编辑工具和必要的系统命令，不另写一套通用接入脚本代替本流程。已有工程若依赖 CocoaPods / Swift Packages，保留其依赖关系，不承诺移除工程本身的依赖。

## 1. 确定参数和操作范围

仅在 macOS 且完整 Xcode 可用时执行修改与编译。检查 `xcodebuild -version`、`plutil`；生成图标时检查 `sips`。非 Mac 环境仅分析文件并提供待执行清单，明确未接入、未编译。

优先读取用户提供的信息及工程，缺失关键参数才询问；子 agent 无法询问时返回主 agent。不要把本插件仓库当作用户的游戏工程。

- 工程：`.xcodeproj` 绝对路径；存在关联 `.xcworkspace` 时同时记录。Cocos 2.x 常见 `build/jsb-default/frameworks/runtime-src/proj.ios_mac/`，3.x 常见 `build/ios/proj/`，Unity 在导出目录。
- target：同时核对 productType 和 iOS 平台，不能仅按名称猜。Cocos 2.x 不选 macOS `-desktop`；Unity 通常是 `Unity-iPhone`。多个候选返回列表。
- SDK：实际 SDK 根目录绝对路径，检查 framework、bundle、源码、Info.plist 和可选资源；不修改 SDK 原文件。
- 最低 iOS 版本：沿用现有版本；不同 target 值不一致时先说明将统一哪些 iOS target / 子工程并确定值。没有现值时提出 13.0 作为候选，待确定后使用，不暗中降级。
- Team ID：SDK 根目录 `Info.plist` 的 `teamid` 优先，否则使用用户 / 调用方给出的值；均无则停止补齐，不使用内置团队。
- 可选处理：SDK 的 `1024.png` 生成图标；LaunchScreen 及背景替换启动图；根目录 `sdk.entitlements` 设置权限文件；用户需要时才执行 Cocos 2.x 蓝色资源文件夹同步。
- 支持用户指定额外字符串 / 数组 build setting、追加设置和项目级设置；确认覆盖还是追加，追加保留已有值及 `$(inherited)`，避免重复。

执行前简述实际 target、最低版本、Team ID 来源及资源替换范围。图标只替换所选 AppIcon，保留整个 `Images.xcassets` 和其他资产。参数已确定且用户已授权的操作直接继续。

## Codex 专用 agent 交接

用户要求独立 agent 时，主 agent 使用已注册的 `xcode_sdk_setup`。尚未注册则读取同包 `../xcode-sdk-agent-setup/SKILL.md` 完成安装并提示新建对话；当前客户端不支持子 agent 时说明限制，不冒充已委派。

交接工程和 SDK 路径、target、最低版本、Team ID 来源、可选资源及蓝色文件夹范围、额外配置、是否编译，以及本 Skill 实际路径。主 agent 处理缺失信息及权限需求，等待结果并汇总；同一工程仅由一个执行者修改。子 agent 不再次委派。

## 2. 直接修改工程

先读取 [references/project-editing.md](references/project-editing.md)，按其对象关联、功能规则和备份要求执行。普通 Skill 调用也按同一规则由主 agent 操作。

先备份所有将修改的主 / 子 `.xcodeproj` 和工程外资源；记录修改前已存在的用户改动和新增文件，保证能精确回滚。使用局部编辑，保持工程格式、objectVersion、已有对象 ID、其他 target 和用户配置；不全文件序列化重写、不做全局正则替换。

基础配置、SDK 引用、Unity / Cocos 分支、Info.plist、图标、启动图、entitlements 和可选资源同步均按参考文档逐项检查；无对应输入的可选项记录为跳过。无需修改启动文件或添加 AppSDK 初始化代码，不修改游戏、引擎、SDK 的源码。

## 3. 检查和编译

先检查工程引用图、路径和资源，确认再次执行不会增加重复引用。对每个修改的 pbxproj 执行 `plutil -lint`，再用 `xcodebuild -list -json -project "<工程>.xcodeproj"` 验证 Xcode 能读取工程；workspace 存在时也核对 workspace 和 scheme。语法检查通过不代表接入正确。

然后读取 [references/build-and-fix.md](references/build-and-fix.md)，关闭签名做真机架构编译。失败时只改工程配置，最多 5 轮；涉及源码、签名或 SDK 文件立即停止。用户明确跳过编译时保留静态检查，并注明未编译；检查失败时停止进入构建，保留诊断及可回滚状态。

## 4. 汇报

返回实际证据，不依赖旧脚本的输出文本：

- 备份清单、恢复方式和新增文件清单；不撤销用户原有修改。
- 实际工程、target、最低版本及涉及的 iOS target / 子工程。
- Team ID 来源、Bundle ID、INFOPLIST_FILE、entitlements 设置或跳过原因。
- 导入 / 复用 / 清理的引用及构建阶段；SDKMessager 所属 target；Unity link/embed 关系。
- AppIcon 路径、生成尺寸、校验结果；说明其他资产保留；启动图和可选资源结果。
- 全部修改文件、配置检查与编译结果、日志路径、逐轮修复及未解决问题。

说明关闭签名的编译不等于真机签名已验证；真机运行前在 Xcode 确认团队，必要时 Clean Build Folder。Cocos / Unity 重新导出覆盖工程后需重新接入。
