# xcode-sdk-setup 插件

把 SDK 目录（AppSDK / TWSDK 等）一键接入 Cocos Creator（2.x / 3.x）或 Unity 导出的 iOS Xcode 工程。

## 能做什么

- 递归导入 SDK 目录：`.framework` 链接并 Embed & Sign，`.bundle` 进 Resources，源码进编译
- 设置 build settings、Bundle ID、Info.plist、签名团队、最低 iOS 版本
- 可选：用 `1024.png` 生成 AppIcon、替换启动图、设置 entitlements
- 修改前自动备份整个 `.xcodeproj`，可一键回滚
- 接入后自动编译验证；出错时只改工程配置尝试修复（最多 5 轮），涉及源代码、签名或 SDK 文件的问题会停下来汇报
- 附带 `xcode-sdk-setup-agent`：重新导出工程后，交给它从接入到编译一次跑完

## 使用方法

支持 Claude 和 Codex。安装后，对助手说「帮我把 SDK 接入 Xcode 工程」「重新导出 iOS 工程后配一下 SDK」即可。助手会优先读取工程已有配置，补齐必要参数后确认工程路径、target、SDK 目录、最低 iOS 版本和 Team ID，再运行脚本并汇总结果。

## 运行要求

- macOS（依赖 `plutil`、`sips`）+ Ruby
- 首次运行会自动安装 `xcodeproj` gem，可能需要输入密码

## 注意

- 脚本内置了一个默认 Team ID。SDK 的 `Info.plist` 里没有 `teamid` 时，请务必用 `--set DEVELOPMENT_TEAM=<你的TeamID>` 指定自己的团队。
- 生成图标时会删除工程自带的 `Images.xcassets`。
- 每次 Cocos / Unity 重新导出 iOS 工程后需要再跑一次。

## 安装

### Codex

```bash
codex plugin marketplace add fuxiaoqiang/skills
codex plugin add xcode-sdk-setup@fxq-skills
```

使用支持插件命令的新版 Codex CLI，安装后新建对话；未出现时重启客户端。Codex 使用共用 Skill 完成参数确认、接入、编译和有限修复，不依赖 Claude 专用子 agent。

### Codex 专用 agent（可选）

安装插件后，新建 Codex 对话，直接说：

> 使用 xcode-sdk-agent-setup，安装 SDK 专用 agent。

Codex 会读取已安装插件中的设置 Skill，并运行同一插件包里的安装脚本。无需克隆本仓库，也无需在游戏工程里寻找脚本。支持插件设置入口的客户端也可运行插件设置（setup），入口指向同一个安装 Skill。

需要 Python 3.9+ 和支持自定义 agent 的 Codex。脚本检查插件已安装并启用，将配置写入 `${CODEX_HOME:-~/.codex}/agents/xcode_sdk_setup.toml`；不修改 `config.toml`、模型或权限。环境要求写入授权时会提示。已有非本工具管理的同名配置不会被覆盖。

安装成功后再新建对话（未识别时重启），在实际游戏工程目录中说：

> 请启动 xcode_sdk_setup 子 agent，使用 xcode-sdk-setup Skill 接入 SDK 并编译验证。工程路径是……，SDK 路径是……。

主 agent 补齐参数后再委派，可从子 agent 活动或 CLI 的 `/subagents` 确认实际启动。仅显示读取 `SKILL.md` 不代表已启动子 agent。当前会话需要允许子 agent。

更新插件并新建对话后说“使用 xcode-sdk-agent-setup，更新 SDK 专用 agent”。更新会自动备份原配置；相同内容重复运行不修改文件。agent 执行时读取父会话继承的当前 Skill，不固定插件缓存版本。

卸载专用配置时说“使用 xcode-sdk-agent-setup，卸载 SDK 专用 agent”。插件和备份会保留，卸载后新建对话。

开发者在仓库中测试时仍可直接运行 `python3 xcode-sdk-plugin/scripts/manage_codex_agent.py install`；普通用户使用上面的对话入口即可。

### Claude

- **Claude 桌面版（Cowork）**：导入仓库根目录的 `xcode-sdk-setup.plugin` 文件。
- **Claude Code**：

  ```text
  /plugin marketplace add fuxiaoqiang/skills
  /plugin install xcode-sdk-setup@fxq-skills
  ```

本插件在本机操作 Xcode 工程。需要 macOS 和完整 Xcode；非 Mac 环境只提供命令和建议，不执行工程配置及编译。
