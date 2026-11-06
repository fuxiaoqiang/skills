# xcode-sdk-setup 插件

把 SDK 目录（AppSDK / TWSDK 等）一键接入 Cocos Creator（2.x / 3.x）或 Unity 导出的 iOS Xcode 工程。

## 能做什么

- 递归导入 SDK 目录：`.framework` 链接并 Embed & Sign，`.bundle` 进 Resources，源码进编译
- 设置 build settings、Bundle ID、Info.plist、签名团队、最低 iOS 版本
- 可选：用 `1024.png` 生成 AppIcon、替换启动图、设置 entitlements
- 修改前自动备份整个 `.xcodeproj`，可一键回滚

## 使用方法

安装后，对 Claude 说「帮我把 SDK 接入 Xcode 工程」「重新导出 iOS 工程后配一下 SDK」即可。Claude 会先确认工程路径、target、SDK 目录、最低 iOS 版本和 Team ID，再运行脚本并汇总结果。

## 运行要求

- macOS（依赖 `plutil`、`sips`）+ Ruby
- 首次运行会自动安装 `xcodeproj` gem，可能需要输入密码

## 注意

- 脚本内置了一个默认 Team ID。SDK 的 `Info.plist` 里没有 `teamid` 时，请务必用 `--set DEVELOPMENT_TEAM=<你的TeamID>` 指定自己的团队。
- 生成图标时会删除工程自带的 `Images.xcassets`。
- 每次 Cocos / Unity 重新导出 iOS 工程后需要再跑一次。

## 安装

- **Claude 桌面版（Cowork）**：导入 `xcode-sdk-setup.plugin` 文件。
- **Claude Code**：把本仓库推到 GitHub 后执行
  ```
  /plugin marketplace add <GitHub用户名>/<仓库名>
  /plugin install xcode-sdk-setup@fxq-skills
  ```
