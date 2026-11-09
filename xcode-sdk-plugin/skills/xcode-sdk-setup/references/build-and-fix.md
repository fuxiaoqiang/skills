# 编译验证与自动修复

接入完成后，用命令行编译一次主 target，出错时按本文规则尝试修复。

## 1. 编译命令

关闭签名，这样只检查代码和工程配置；签名问题由用户在 Xcode 里处理。编译目标用真机架构，因为很多 SDK 的 framework 没有模拟器架构。

在 `.xcodeproj` 所在目录执行：

```bash
# 有 .xcworkspace（如 Unity + CocoaPods）时改用 -workspace <名>.xcworkspace -scheme <scheme>
xcodebuild -project <工程>.xcodeproj -target <target> -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  > sdk-build.log 2>&1; echo "exit=$?"
```

- Cocos 首次编译引擎可能超过 10 分钟：用后台方式运行，每隔一段时间查看 `tail -5 sdk-build.log`，直到出现 `** BUILD SUCCEEDED **` 或 `** BUILD FAILED **`。
- 提取错误：`grep -nE "error:|ld: |Undefined symbols|duplicate symbol|\*\* BUILD" sdk-build.log | head -60`。只看第一个真正的错误，后面的错误常常是它引起的连锁反应。

## 2. 修复循环

- 最多尝试 **5 轮**（修改 → 重新编译）。每轮只改一处，改完立即重编，确认这处修改是否有效。
- 某次修改没有让错误减少或变好，就撤销这次修改再试别的办法。
- 记录每一轮：错误摘要、做了什么修改、结果。最后完整汇报给用户。
- 5 轮后仍失败，或遇到下面「必须停下」的情况，停止并汇报：最后的错误原文、已尝试的修改、建议用户怎么处理。

### 可以自动修复的（只改工程配置）

优先用脚本的选项重跑来改，例如 `--append` / `--set` / `--ios-min`；需要单独改某个 setting 时用 `xcodeproj` gem 写一小段 Ruby。**不要手工编辑 `project.pbxproj` 文本。**

| 错误特征 | 处理 |
|---|---|
| `Undefined symbols` 且符号来自 ObjC 类别（category） | `--append OTHER_LDFLAGS=-ObjC` |
| `Undefined symbols` 指向系统库（如 `_inflate`、`sqlite3_`、`std::`） | 追加对应库：`-lz`、`-lsqlite3`、`-lc++` |
| `Undefined symbols` 指向系统框架类（如 `_OBJC_CLASS_$_WKWebView`、`StoreKit`、`AdSupport`） | `--append OTHER_LDFLAGS=-framework,WebKit` 这类，按符号所属框架追加 |
| `framework not found X` / `'X/X.h' file not found` | 检查 `FRAMEWORK_SEARCH_PATHS` / `HEADER_SEARCH_PATHS` 是否包含 SDK 目录（相对 `$(SRCROOT)`），缺了就 `--append` |
| `Swift` 相关链接错误（`swiftCore`、`__swift_FORCE_LOAD`） | `--set ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES`，必要时在 `LIBRARY_SEARCH_PATHS` 追加 `$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)` |
| `is only available on iOS X or newer` / `compiling for iOS N, but module was built for iOS M` | 用 `--ios-min M` 提高最低版本；汇报里写明改了版本 |
| 引擎 target 报 `cannot be specialized: Users are not allowed to specialize this standard library entity [-Winvalid-specialization]` | 正常情况下脚本已自动处理。仍出现时，给报错的那个 target 的 `OTHER_CPLUSPLUSFLAGS` 追加 `-Wno-invalid-specialization`（用 xcodeproj gem 改，保留原值）。**不要修改引擎源码**，例如 `half.h` |
| `ENABLE_BITCODE` 相关报错 | `--set ENABLE_BITCODE=NO` |
| `duplicate symbol`，且是 SDK 源文件被同时加进了两个 target | 从错误的 target 移除该文件的编译引用 |

### 必须停下、不自己改的

- 签名、证书、描述文件、Team 相关的错误（应该已被 `CODE_SIGNING_ALLOWED=NO` 排除；出现说明配置异常）。
- 需要修改**任何源代码文件**的错误：引擎代码、SDK 源码、`AppDelegate.mm` / `AppController.mm` / `UnityAppController.mm`、游戏代码，包括 `UIScene life cycle is required` 这类需要改启动代码的情况。
- 需要修改、删除 SDK 目录里的文件，或 SDK 里缺文件。
- 与 SDK 接入无关的错误（例如引擎本身编译失败，回滚到备份后同样失败）。
- 不确定原因的错误。不要靠猜测反复改配置。

## 3. 汇报

在第 3 步总结之后追加：

- 编译结果：成功 / 失败，耗时；
- 每一轮修复：错误 → 修改 → 结果；
- 最终相对接入脚本运行后额外做了哪些修改（方便用户审查）；
- 失败时：最后的错误原文（截取关键几行）和建议。
