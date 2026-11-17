# FXQ Skills

面向 Claude 和 Codex 的开发工具插件仓库。两边共用 agent 接入规则和参考文档。

目前包含 **xcode-sdk-setup**：将 SDK 接入 Cocos Creator / Unity 导出的 iOS Xcode 工程，并编译验证。详细能力、环境要求和注意事项见 [插件说明](xcode-sdk-plugin/README.md)。

## SDK 接入方式（0.6.0 起）

由 agent 读取实际工程，直接局部编辑 `project.pbxproj` 和资源，不再提供或调用 Ruby 接入脚本。无需安装 Ruby、gem 或第三方工程解析库；已有游戏工程本身依赖的 CocoaPods / Swift Packages 不在本插件的移除范围内。专用 agent 的安装、更新工具仍使用 Python 3.9+。

保留 framework/bundle/源码导入、基础及自定义 build settings、最低版本与子工程同步、Info.plist / Bundle ID / Team、Unity 双 target、Cocos 引擎参数、启动图、entitlements，以及自动检测 hortor 的蓝色资源文件夹同步。可在提示中要求追加或覆盖指定设置、同步项目级设置。

提供一张 `1024.png` 即可按图标模板生成 AppIcon；仅替换所选图标集，保留整个 `Images.xcassets` 及其他图片。动态 framework 配置 Embed & Sign，静态 framework 只链接。重复接入复用正确引用，修改前备份全部受影响的主/子工程和外部资源，随后检查引用关系、工程加载并编译；失败时最多进行 5 轮工程配置修复。

旧版用户运行一次统一安装入口迁移固定 agent 配置并新建对话；后续工作流更新无需单独同步 agent。所有变更会汇报，需源码、签名或 SDK 原文件修改的问题停止交回用户。

## 自动同步蓝色资源目录（0.6.2 起）

接入 SDK 时会检查工程目录、上一级目录及它们的 `data/` 子目录，并结合工程已有引用寻找 `hortor`。例如工程在 `proj/`，同级有 `data/hortor` 时，会自动将 `data/` 下存在的 `jsb-adapter`、`assets`、`src`、`hortor` 添加成蓝色文件夹引用并加入主 target Resources，无需再指定 `--Asset`。

已有正确引用会复用，旧的重复资源挂载会清理；不删除磁盘资源，不导入同级其他 JS 文件。未发现 hortor 时跳过；目录缺失会逐项说明；多个候选无法唯一确定时才询问。用户也可以明确要求跳过资源同步。

## 安装 SDK 接入 agent

用户只需要安装一次 **SDK 接入 agent**。工作流包由安装器自动准备，不需要先手动安装插件，也不需要自己克隆仓库。

环境要求：Mac、完整 Xcode、支持自定义 agent 和插件命令的 Codex、Python 3.9+、Git。SDK 接入本身无需 Ruby 或 gem。

### 安装

可以直接对 Codex 说：

> 请按照 https://github.com/fuxiaoqiang/skills 的 README 安装 SDK 接入 agent，完成工作流准备和 agent 注册。

也可以在终端下载统一入口并运行：

```bash
sdk_agent_installer=$(mktemp -t fxq-sdk-agent)
curl -fL https://raw.githubusercontent.com/fuxiaoqiang/skills/main/install_agent.py -o "$sdk_agent_installer"
python3 "$sdk_agent_installer" install
```

curl 下载失败时不要继续执行。安装器会获取完整安装文件，自动添加 FXQ 来源、安装并启用 SDK 工作流包，再注册 `xcode_sdk_setup`。首次使用可能需要网络和配置目录写入授权。它不修改模型、沙箱或权限设置；同名非本工具配置会拒绝覆盖。

已克隆仓库的开发者也可直接运行 `python3 install_agent.py install`。重复安装会保持固定入口一致；旧版受管理的 agent 会先备份再迁移，不需要额外执行一轮 agent 更新。

### 开始工作

安装完成后新建 Codex 对话，未识别时重启客户端。在自己的游戏工程目录中说：

> 请启动 xcode_sdk_setup agent，接入 SDK 并编译验证。工程路径是 `/实际路径/Game.xcodeproj`，SDK 目录是 `/实际路径/SDK`。

将图标源文件 `1024.png` 放在 SDK 目录。其他可选输入是 target、最低 iOS 版本、Apple Team ID；能从工程唯一确定的参数会自动读取，缺项时再询问。SDK Info.plist 的 teamid 优先，没有时需提供自己的团队。

agent 会直接修改工程、生成图标并编译。图标只替换目标 AppIcon，保留整个 Images.xcassets。需要当前会话允许子 agent，可通过子 agent 活动或 CLI 的 `/subagents` 确认实际启动。

### 更新

agent 的本地配置是固定入口，任务规则来自当前已安装的工作流包。常规更新只需刷新并更新该包，不需要再单独更新 agent：

```bash
codex plugin marketplace upgrade fxq-skills
```

在客户端插件目录确认 `xcode-sdk-setup` 已更新后新建对话。可以用 `codex plugin list --json` 检查版本及启用状态；来源刷新本身不等于已核对包版本。

也可以重新下载上述统一安装入口，运行最后一条命令时将 `install` 换成 `update`：安装器统一刷新来源、安装工作流包并检查 agent 入口。若仍是旧版包，检查远程是否已发布，并在客户端完成更新。

从 0.6.0 及更早版本迁移时，运行一次新的 `install` 或 `update`，将旧 agent 转成固定入口（自动备份）；此后规则随工作流包更新，无需再单独同步 agent。

### 卸载

重新下载统一入口，将最后一个参数换成 `uninstall`；本地仓库可执行 `python3 install_agent.py uninstall`。这会删除本工具管理的 agent 配置，保留备份和工作流包。卸载包可再执行 `codex plugin remove xcode-sdk-setup@fxq-skills`，然后新建对话。

### 安装问题

- `command not found: codex`：先安装 CLI 或将其可执行文件目录加入 PATH，再新开终端。
- 网络失败：安装器会报告失败，不应当宣称已安装。检查 GitHub 和 Codex 来源访问后重试。
- 同名配置冲突：先自行确认原配置用途，安装器不会覆盖其他工具的 agent。
- 新对话找不到 agent：检查安装输出路径、是否使用同一个 CODEX_HOME，并确认客户端支持自定义 agent。

## 实现说明

插件是 agent 的内部工作流分发载体。安装器自动准备它，用户入口始终是“安装 SDK 接入 agent”。用户配置位于 `~/.codex/agents/xcode_sdk_setup.toml`（遵循 CODEX_HOME），只保存固定加载指令，不复制具体版本的接入规则，也不绑定某个缓存版本路径。规则由当前会话继承的 `xcode-sdk-setup` Skill 提供，因此包更新后需要新建对话。

已安装工作流包的用户也可以说“使用 xcode-sdk-agent-setup，安装 SDK 专用 agent”，它调用相同安装器。

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
install_agent.py                       用户统一安装入口
scripts/package_plugin.py              重建 Claude 桌面安装包
```

Codex 通过统一安装入口自动准备工作流并注册专用子 agent。Claude 专用子 agent 保留给 Claude 使用。

## 本地验证与发布

在仓库根目录添加本地来源并安装（这会修改本机 Codex 插件配置）：

```bash
codex plugin marketplace add .
codex plugin add xcode-sdk-setup@fxq-skills
```

本地验证和远程分发使用相同的 marketplace 名称；测试时请使用独立 Codex 配置，或先移除同名远程来源，避免冲突。

发布前：

1. 默认递增版本号最后一位，例如 `0.6.0 → 0.6.1 → 0.6.2`；需要提升前两位时另行确定。同步修改 `xcode-sdk-plugin/plugin.json` 和 `.claude-plugin/plugin.json` 的版本与公共元数据。
2. 更新共用 Skill、agent 配置、参考文档及安装说明。
3. 运行 `python3 scripts/package_plugin.py`，重建根目录的 `.plugin` 包。
4. 在 Mac 上用真实导出工程验证接入与编译，再提交源码和安装包、推送 GitHub。建议为发布版本创建 Git tag。

本仓库的 Xcode 接入功能依赖 macOS 和完整 Xcode，不适用于 Linux 云端直接执行。

配置格式参考 [OpenAI 插件打包与分发文档](https://developers.openai.com/plugins/build/plugins)。

## License

[MIT](LICENSE)
