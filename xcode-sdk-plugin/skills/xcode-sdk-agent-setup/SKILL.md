---
name: xcode-sdk-agent-setup
description: 在 Codex 中安装、更新或卸载 SDK 专用子 agent（xcode_sdk_setup）。用户说“安装 SDK 专用 agent”“配置 SDK agent”“更新 SDK agent”“卸载 SDK agent”时使用；实际接入 Xcode SDK 使用 xcode-sdk-setup。
---

# SDK 专用 agent 设置

此入口用于 Codex。Claude 使用插件自带的 Claude agent，不需要安装 Codex 配置。

## 从已安装的插件包执行

以当前加载的本文件所在目录为 `<SKILL_DIR>`，插件根目录是其上两级。使用同一个插件包里的 `scripts/manage_codex_agent.py` 和 `codex-agents/xcode_sdk_setup.toml`。

不要从当前游戏工程目录查找同名脚本，不搜索开发者的其他仓库，不让用户重新克隆仓库，不硬编码缓存版本或用户目录。若同包脚本或模板缺失，报告插件不完整，让用户更新或重新安装插件；不要临时下载并执行其他来源的脚本。

按用户意图选择动作：安装或迁移固定入口使用 `install`，统一更新使用 `update`，卸载使用 `uninstall`。安装器自动准备工作流包并备份迁移旧版入口，用户无需分开安装插件与 agent。非本工具管理的同名文件冲突时停止，不覆盖。

```bash
python3 "<SKILL_DIR>/../../scripts/manage_codex_agent.py" install
```

更新和卸载只替换最后一个参数。执行前简要说明会写入用户 Codex agents 目录（卸载则删除专用配置）；已有用户请求即为本次设置意图。若环境需要文件写入授权，按当前权限流程申请，不绕过限制。脚本需要 Python 3.9+，安装和更新会自动检查并准备工作流包。固定入口按当前已加载的 Skill 执行，不复制具体接入规则，常规包更新后只需新建对话，无需单独同步 agent。

## 核对并交接

检查命令退出状态及输出；成功才报告安装完成。配置路径由脚本输出，默认是 `~/.codex/agents/xcode_sdk_setup.toml`，遵循 `CODEX_HOME`。脚本不修改模型、权限或 config.toml。

提示用户新建 Codex 对话，未识别时重启。然后可说：

> 请启动 xcode_sdk_setup 子 agent，使用 xcode-sdk-setup Skill 接入 SDK 并编译验证。工程路径是……，SDK 路径是……。

安装配置不代表本次已启动子 agent，也不代表工程已经接入。当前会话不能发现新配置时，不用默认 agent 冒充专用 agent。
