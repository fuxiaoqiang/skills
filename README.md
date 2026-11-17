# FXQ Skills

面向 Claude 和 Codex 的开发工具插件仓库。两边共用 Skill、脚本和参考文档。

目前包含 **xcode-sdk-setup**：将 SDK 接入 Cocos Creator / Unity 导出的 iOS Xcode 工程，并编译验证。详细能力、环境要求和注意事项见 [插件说明](xcode-sdk-plugin/README.md)。

## Codex 安装

安装支持插件命令的新版 Codex CLI，然后执行：

```bash
codex plugin marketplace add fuxiaoqiang/skills
codex plugin add xcode-sdk-setup@fxq-skills
```

也可以添加仓库来源后，在桌面客户端的插件目录中找到 FXQ Skills 并安装。新建对话后使用；未出现时重启客户端。

对 Codex 说：

> 使用 xcode-sdk-setup，把 SDK 接入这个 Cocos / Unity 导出的 iOS 工程并编译验证。

可在提示中附上工程路径、SDK 目录、target、最低 iOS 版本和 Team ID。能够从工程确定的参数会自动读取，缺少关键信息时再询问。

更新仓库来源：

```bash
codex plugin marketplace upgrade fxq-skills
```

更新来源后，在插件目录检查插件更新；必要时重新安装并新建对话。这里提供的是 GitHub 仓库分发，不代表已经上架官方公共插件目录。

## Codex 专用 agent（可选）

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
  skills/xcode-sdk-setup/               两边共用的 Skill 和脚本
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
2. 更新共用 Skill、脚本、参考文档及安装说明。
3. 运行 `python3 scripts/package_plugin.py`，重建根目录的 `.plugin` 包。
4. 在 Mac 上用真实导出工程验证接入与编译，再提交源码和安装包、推送 GitHub。建议为发布版本创建 Git tag。

本仓库的 Xcode 接入功能依赖 macOS、Xcode 和 Ruby，不适用于 Linux 云端直接执行。

配置格式参考 [OpenAI 插件打包与分发文档](https://developers.openai.com/plugins/build/plugins)。

## License

[MIT](LICENSE)
