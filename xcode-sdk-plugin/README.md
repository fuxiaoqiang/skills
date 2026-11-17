# xcode-sdk-setup 插件

把 SDK 目录（AppSDK / TWSDK 等）一键接入 Cocos Creator（2.x / 3.x）或 Unity 导出的 iOS Xcode 工程。

## 能做什么

- 递归导入 SDK 目录：`.framework` 链接，动态 framework 配置 Embed & Sign，`.bundle` 进 Resources，源码进编译
- 设置 build settings、Bundle ID、Info.plist、签名团队、最低 iOS 版本
- 可选：用 `1024.png` 生成 AppIcon、替换启动图、设置 entitlements
- 修改前备份主工程、所有将修改的子工程和图标等外部资源，并提供恢复清单
- 接入后自动编译验证；出错时只改工程配置尝试修复（最多 5 轮），涉及源代码、签名或 SDK 文件的问题会停下来汇报
- 附带 Claude 的 `xcode-sdk-setup-agent` 和可安装的 Codex `xcode_sdk_setup`：重新导出工程后，交给它从接入到编译一次跑完

## 使用方法

支持 Claude 和 Codex。安装后，对助手说「帮我把 SDK 接入 Xcode 工程」「重新导出 iOS 工程后配一下 SDK」即可。助手会优先读取工程已有配置，补齐必要参数后确认工程路径、target、SDK 目录、最低 iOS 版本和 Team ID，再直接编辑工程、校验并编译，最后汇总结果。

## 运行要求

- macOS + 完整 Xcode，使用自带的 `plutil`、`sips` 和 `xcodebuild`
- SDK 接入不依赖 Ruby 或 `xcodeproj` gem；专用 agent 安装工具仍需要 Python 3.9+

## 注意

- SDK `Info.plist` 没有 `teamid` 时需提供自己的 Team ID，不再使用内置默认团队。
- 生成图标时只替换所选 AppIcon 图标集，保留 `Images.xcassets` 及其他资产；修改前备份图标集。
- 每次 Cocos / Unity 重新导出 iOS 工程后需要再跑一次。

## SDK 接入方式（0.6.0 起）

由 agent 读取实际工程，直接局部编辑 `project.pbxproj` 和资源，不再提供或调用 Ruby 接入脚本。无需安装 Ruby、gem 或第三方工程解析库；已有游戏工程本身依赖的 CocoaPods / Swift Packages 不在本插件的移除范围内。专用 agent 的安装、更新工具仍使用 Python 3.9+。

保留 framework/bundle/源码导入、基础及自定义 build settings、最低版本与子工程同步、Info.plist / Bundle ID / Team、Unity 双 target、Cocos 引擎参数、启动图、entitlements，以及可选的 Cocos 2.x 蓝色资源文件夹同步。可在提示中要求追加或覆盖指定设置、同步项目级设置、同步 jsb-adapter/assets/src/hortor 资源目录。

提供一张 `1024.png` 即可按图标模板生成 AppIcon；仅替换所选图标集，保留整个 `Images.xcassets` 及其他图片。动态 framework 配置 Embed & Sign，静态 framework 只链接。重复接入复用正确引用，修改前备份全部受影响的主/子工程和外部资源，随后检查引用关系、工程加载并编译；失败时最多进行 5 轮工程配置修复。

从旧版升级时，请先更新插件，再通过 `xcode-sdk-agent-setup` 更新专用 agent 配置并新建对话；旧对话及旧版 agent 可能仍要求调用 Ruby 脚本。所有变更会汇报，需源码、签名或 SDK 原文件修改的问题停止交回用户。

## Codex 从零开始

### 1. 准备环境

- Mac + 完整 Xcode（接入和编译不能在 Linux 云端直接执行）。
- SDK 接入使用 agent 直接编辑工程，不需要 Ruby、`xcodeproj` gem 或第三方工程解析库。
- Python 3.9+（安装、更新专用 agent 时使用）。
- 支持插件命令和自定义 agent 的 Codex CLI / 客户端。

先在终端检查：

```bash
codex --version
python3 --version
xcodebuild -version
```

如果出现 `zsh: command not found: codex`，说明 CLI 未安装或尚未加入终端 PATH。先安装 CLI，或将本机已有的 CLI 可执行文件所在目录加入 `~/.zshrc` 的 PATH，再新开终端重试。不要复制其他电脑的绝对路径。

### 2. 安装插件

在任意目录执行，不需要克隆本仓库：

```bash
codex plugin marketplace add fuxiaoqiang/skills
codex plugin add xcode-sdk-setup@fxq-skills
```

也可以添加来源后，在桌面客户端的插件目录找到 FXQ Skills 并安装 `xcode-sdk-setup`。这里是 GitHub 仓库分发，不代表已上架官方公共插件目录。

### 3. 安装专用 agent

安装插件后新建 Codex 对话，说：

> 使用 xcode-sdk-agent-setup，安装 SDK 专用 agent。

Codex 会从已下载的插件包运行安装脚本，无需手动查找脚本或再次克隆仓库。支持插件设置入口的客户端也可以运行插件设置（setup）。若环境提示写入用户配置需要授权，允许本次安装即可。

脚本将配置写入 `~/.codex/agents/xcode_sdk_setup.toml`；设置了 `CODEX_HOME` 时则写入该目录下的 `agents/`。已有非本工具管理的同名配置不会被覆盖，脚本不修改 `config.toml`、模型或权限。

### 4. 使用专用 agent 接入 SDK

安装成功后再新建对话，未识别时重启客户端。打开自己的游戏导出工程目录，并提供实际路径：

> 请启动 xcode_sdk_setup 子 agent，使用 xcode-sdk-setup Skill 接入 SDK 并编译验证。工程路径是 `/实际路径/Game.xcodeproj`，SDK 目录是 `/实际路径/SDK`。

如果已知，也可以附上 target、最低 iOS 版本和 Apple Team ID。助手会优先读取工程配置，缺少必要信息时再询问，并在操作前告知图标等资源的处理影响。

当前会话需要允许子 agent；可以从子 agent 活动或 CLI 的 `/subagents` 确认实际启动。仅显示读取 `SKILL.md` 不代表已启动子 agent。

如果不需要独立子 agent，可跳过第 3 步，直接说：

> 使用 xcode-sdk-setup，把 SDK 接入这个 Cocos / Unity 导出的 iOS 工程并编译验证。

## Codex 更新插件和 agent

插件包和用户目录中的专用 agent 配置需要分别更新。

### 1. 更新插件来源和插件包

发布者先提交并推送最新改动到 GitHub，用户才能获取新版本。在终端执行：

```bash
codex plugin marketplace upgrade fxq-skills
```

随后在客户端插件目录检查 `xcode-sdk-setup` 的版本并完成更新；必要时重新安装插件。可以用下面的命令检查安装记录：

```bash
codex plugin list --json
```

检查 `xcode-sdk-setup@fxq-skills` 的版本及启用状态。仅刷新来源不应当被视作已经验证所有已安装文件都是最新版。

### 2. 同步专用 agent 配置

插件更新完成后新建对话，说：

> 使用 xcode-sdk-agent-setup，更新 SDK 专用 agent。

更新会自动备份旧配置；相同内容重复运行不会修改文件。未安装专用 agent 的用户可跳过这一步。agent 不固定插件缓存版本，执行时读取父会话继承的当前 Skill。

### 3. 开始使用新版

更新成功后再新建对话，未识别时重启客户端，然后继续让 `xcode_sdk_setup` 子 agent 接入 SDK。

如果看不到 `xcode-sdk-agent-setup`，先检查是否安装并启用了含此入口的插件版本（`0.5.0` 起提供），然后新建对话；不要在游戏工程里找安装脚本。

## 卸载专用 agent

对 Codex 说：

> 使用 xcode-sdk-agent-setup，卸载 SDK 专用 agent。

这会移除专用配置，插件和更新备份仍保留。卸载后新建对话。

开发者在仓库中测试时仍可运行 `python3 xcode-sdk-plugin/scripts/manage_codex_agent.py install`，更新和卸载分别将最后一个参数换成 `update`、`uninstall`。普通用户使用对话入口即可。

## Claude 安装

- **Claude 桌面版（Cowork）**：导入仓库根目录的 `xcode-sdk-setup.plugin` 文件。
- **Claude Code**：

  ```text
  /plugin marketplace add fuxiaoqiang/skills
  /plugin install xcode-sdk-setup@fxq-skills
  ```

本插件在本机操作 Xcode 工程。需要 macOS 和完整 Xcode；非 Mac 环境只提供命令和建议，不执行工程配置及编译。
