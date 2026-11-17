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
  skills/xcode-sdk-setup/               两边共用的 Skill 和脚本
scripts/package_plugin.py              重建 Claude 桌面安装包
```

Codex 直接执行共用 Skill 中的完整流程；Claude 专用子 agent 保留给 Claude 使用。

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
