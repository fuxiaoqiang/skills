# 编译验证与自动修复

接入完成后，用命令行编译一次主 target，出错时按本文规则尝试修复。

## 1. 编译命令

关闭签名，这样只检查代码和工程配置；签名问题由用户在 Xcode 里处理。编译目标用真机架构，因为很多 SDK 的 framework 没有模拟器架构。

先用带实际 `-project` / `-workspace` 参数的 `xcodebuild -list -json` 核对 scheme 和配置。在 `.xcodeproj` 所在目录执行，使用实际路径并引用参数：

```bash
# 有关联 workspace 时使用下方 workspace 命令，不能继续构建绕过它的 project。
xcodebuild -project "<工程>.xcodeproj" -scheme "<scheme>" -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  > sdk-build.log 2>&1
sdk_build_status=$?
printf 'build exit=%s\n' "$sdk_build_status"
# 立即记录退出码，不以日志末行代替退出状态。

# workspace 工程：
xcodebuild -workspace "<工程>.xcworkspace" -scheme "<scheme>" -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  > sdk-build.log 2>&1
sdk_build_status=$?
printf 'build exit=%s\n' "$sdk_build_status"
```

- 如果工程没有可用 scheme，改用 `-project "<工程>.xcodeproj" -target "<target>" -configuration Debug -sdk iphoneos`（不带 `-destination`）；workspace 必须确定有效 scheme。不要为了编译擅自改用户共享 scheme。
- Cocos 首次编译引擎可能超过 10 分钟：用后台方式运行，每隔一段时间查看 `tail -5 sdk-build.log`，直到出现 `** BUILD SUCCEEDED **` 或 `** BUILD FAILED **`。
- 提取错误：`grep -nE "error:|ld: |Undefined symbols|duplicate symbol|\*\* BUILD" sdk-build.log | head -60`。只看第一个真正的错误，后面的错误常常是它引起的连锁反应。

Unity / 团结使用实际主 App 的 scheme（如 Unity-iPhone / Tuanjie-iPhone），不得将 Tests、GameAssembly 或引擎 framework 的 scheme 当作 App 接入验证。

## 2. 修复循环

- 最多尝试 **5 轮**（修改 → 重新编译）。每轮只改一处，改完立即重编，确认这处修改是否有效。
- 某次修改没有让错误减少或变好，就撤销这次修改再试别的办法。
- 记录每一轮：错误摘要、做了什么修改、结果。最后完整汇报给用户。
- 5 轮后仍失败，或遇到下面「必须停下」的情况，停止并汇报：最后的错误原文、已尝试的修改、建议用户怎么处理。

### 可以自动修复的（只改工程配置）

按 `project-editing.md` 的对象关联规则直接局部编辑 `project.pbxproj`。追加设置保留原值和 `$(inherited)`，不安装 Ruby / gem，也不调用旧脚本。每轮编辑后先通过 `plutil -lint` 和工程加载检查，再重新编译。

| 错误特征 | 处理 |
|---|---|
| `Undefined symbols` 且符号来自 ObjC 类别（category） | 在对应 target 的 OTHER_LDFLAGS 追加 `-ObjC` |
| `Undefined symbols` 指向系统库（如 `_inflate`、`sqlite3_`、`std::`） | 追加对应库：`-lz`、`-lsqlite3`、`-lc++` |
| `Undefined symbols` 指向系统框架类（如 `_OBJC_CLASS_$_WKWebView`、`StoreKit`、`AdSupport`） | 在 OTHER_LDFLAGS 追加 `-framework`、`WebKit` 这类参数对，按符号所属框架追加 |
| `framework not found X` / `'X/X.h' file not found` | 检查 `FRAMEWORK_SEARCH_PATHS` / `HEADER_SEARCH_PATHS` 是否包含 SDK 目录（相对 `$(SRCROOT)`），缺了就保留原值追加 |
| `Swift` 相关链接错误（`swiftCore`、`__swift_FORCE_LOAD`） | 设置 `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES`，必要时在 `LIBRARY_SEARCH_PATHS` 追加 `$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)` |
| `is only available on iOS X or newer` / `compiling for iOS N, but module was built for iOS M` | 明确告知提高最低版本至 M 的影响，确定后同步相关 iOS target / 子工程；汇报里写明改了版本 |
| 引擎 target 报 `cannot be specialized: Users are not allowed to specialize this standard library entity [-Winvalid-specialization]` | 若接入时未覆盖该 target，给报错的那个 target 的 `OTHER_CPLUSPLUSFLAGS` 追加 `-Wno-invalid-specialization`（直接修改其构建配置，保留原值）。**不要修改引擎源码**，例如 `half.h` |
| `ENABLE_BITCODE` 相关报错 | 设置 `ENABLE_BITCODE=NO` |
| `duplicate symbol`，且是 SDK 源文件被同时加进了两个 target | 从错误的 target 移除该文件的编译引用 |

### 必须停下、不自己改的

- 签名、证书、描述文件、Team 相关的错误（应该已被 `CODE_SIGNING_ALLOWED=NO` 排除；出现说明配置异常）。
- 需要修改**任何源代码文件**的错误：引擎代码、SDK 源码、`AppDelegate.mm` / `AppController.mm` / `UnityAppController.mm` / `TuanjieAppController.mm`、游戏代码，包括 `UIScene life cycle is required` 这类需要改启动代码的情况。
- 需要修改、删除 SDK 目录里的文件，或 SDK 里缺文件。
- 与 SDK 接入无关的错误（例如引擎本身编译失败，回滚到备份后同样失败）。
- 不确定原因的错误。不要靠猜测反复改配置。

## 3. 汇报

在最终汇报中包含：

- 编译结果：成功 / 失败，耗时；
- 每一轮修复：错误 → 修改 → 结果；
- 最初接入之后每轮编译修复额外做了哪些修改（方便用户审查）；
- 失败时：最后的错误原文（截取关键几行）和建议。
