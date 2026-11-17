# FXQ Skills

面向 Claude 和 Codex 的开发工具插件仓库。两边共用 agent 接入规则和参考文档。

目前包含 **xcode-sdk-setup**：将 SDK 接入 Cocos Creator / Unity 导出的 iOS Xcode 工程，并编译验证。详细能力、环境要求和注意事项见 [插件说明](xcode-sdk-plugin/README.md)。

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

Claude Code：

```text
/plugin marketplace add fuxiaoqiang/skills
/plugin install xcode-sdk-setup@fxq-skills
```

Claude 桌面版（Cowork）：下载仓库中的 [xcode-sdk-setup.plugin](xcode-sdk-setup.plugin) 文件并导入。

## 仓库结构

```text
.agents/plugins/marketplace.json        Codex 插件目录
.claude-plugin/marketplace.json         Claude 插件目录
xcode-sdk-plugin/
  plugin.json                          通用插件清单
  .claude-plugin/plugin.json           Claude 插件清单
  agents/                              Claude 专用子 agent
  codex-agents/                        Codex 专用子 agent 模板
  scripts/manage_codex_agent.py         agent 安装、更新和卸载
  skills/xcode-sdk-setup/               两边共用的直接接入规则和参考文档
  skills/xcode-sdk-agent-setup/         Codex agent 安装、更新、卸载入口
scripts/package_plugin.py              重建 Claude 桌面安装包
```

Codex 默认执行共用 Skill，也可通过安装脚本注册专用子 agent。Claude 专用子 agent 保留给 Claude 使用。

## 本地验证与发布

在仓库根目录添加本地来源并安装（这会修改本机 Codex 插件配置）：

```bash
codex plugin marketplace add .
codex plugin add xcode-sdk-setup@fxq-skills
```

本地验证和远程分发使用相同的 marketplace 名称；测试时请使用独立 Codex 配置，或先移除同名远程来源，避免冲突。

发布前：

1. 同步修改 `xcode-sdk-plugin/plugin.json` 和 `.claude-plugin/plugin.json` 的版本与公共元数据。
2. 更新共用 Skill、agent 配置、参考文档及安装说明。
3. 运行 `python3 scripts/package_plugin.py`，重建根目录的 `.plugin` 包。
4. 在 Mac 上用真实导出工程验证接入与编译，再提交源码和安装包、推送 GitHub。建议为发布版本创建 Git tag。

本仓库的 Xcode 接入功能依赖 macOS 和完整 Xcode，不适用于 Linux 云端直接执行。

配置格式参考 [OpenAI 插件打包与分发文档](https://developers.openai.com/plugins/build/plugins)。

## License

[MIT](LICENSE)
