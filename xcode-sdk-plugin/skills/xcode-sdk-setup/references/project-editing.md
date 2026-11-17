# 直接编辑 Xcode 工程

本文件替代原 Ruby 接入逻辑。按工程现有结构实施局部修改，不安装第三方解析库。命令中的路径均应使用实际值并正确引用。

## 备份和恢复

1. 读取主工程及其 PBXFileReference 引用的 `.xcodeproj`，递归去重，解析相对路径时考虑 group、sourceTree 和 SRCROOT，不能只取 path 字符串。建立要修改的 target / configuration 清单。
2. 修改前将每个会写入的 `.xcodeproj` 完整复制到不会覆盖旧备份的时间戳目录。工程外将替换的 AppIcon 和其他资源同样备份；SDK 文件只读。
3. 记录原有文件和新增文件 / 对象。恢复工程目录及已替换资源时使用对应备份；新建资源只删除本次新建的部分。不要以 git reset/checkout 撤销用户原有改动，也不要删除整个资产目录。
4. 后续发现需要修改新文件或其他子工程时，先补充备份。编译修复同样记录每一轮变更，回退只撤销本轮。

## pbxproj 对象关联和局部编辑

- 阅读 OpenStep plist 的 `objects`、`rootObject`，按对象 ID 追踪结构；注释和显示名称不作为唯一身份。
- PBXNativeTarget 的 `buildConfigurationList` → XCConfigurationList → XCBuildConfiguration。只改实际属于目标的配置，不能按配置名全局替换 Debug/Release。
- 新对象 ID 使用未占用的 24 位十六进制值（可用系统 `uuidgen` 生成并去掉连字符、截取 24 位），与现有 ID 集合核对。已有正确对象保持原 ID。
- PBXFileReference 由 PBXGroup.children 组织；Sources、Resources、Frameworks、CopyFiles 等 phase 的 `files` 存放 PBXBuildFile ID，后者 `fileRef` 指向文件对象；phase ID 必须挂到对应 target 的 `buildPhases`。
- 文件路径优先相对工程 / 分组、保留可移植性。含空格、变量或特殊字符时遵循现有 plist 的字符串转义规则，不把 shell 展开结果写成 Xcode 变量。
- 按解析后的实际文件路径复用引用。同一文件在不同 phase / target 可以有各自 PBXBuildFile，但同一 phase 不重复添加同一文件。
- 清理失效引用时先找出所有入边，移除关联 build file、phase.files 和 group.children 后再删除对象；有其他 target 使用的正确共享引用要保留，不能留下悬空引用。
- 只清理当前 SDK 目录下的旧 / 错误 / 重复接入引用。与其他 SDK、其他 target 无关的引用、依赖和构建阶段保留。重复运行以修复和复用为主，不每次删光重建。
- 不改变工程版本或将整个 pbxproj 转成 JSON/XML。`plutil -convert json -o -` 可用于只读分析，若当前格式不支持则直接读取原文件，不为分析重写工程。

## 基础 build settings

对选中的主 App target 的所有构建配置设置以下值；用户明确指定的覆盖值优先。只有用户要求项目级设置时，才将这组基础值也写入项目配置。

| 设置 | 值 / 处理 |
|---|---|
| ENABLE_BITCODE | NO |
| GCC_GENERATE_DEBUGGING_SYMBOLS | YES |
| TARGETED_DEVICE_FAMILY | `1,2` |
| SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD | NO |
| CODE_SIGN_STYLE | Automatic |
| CODE_SIGN_IDENTITY | Apple Development |
| DEVELOPMENT_TEAM | 确认的 SDK plist teamid 或用户提供值，无内置默认 |
| FRAMEWORK_SEARCH_PATHS | 保留已有路径和 `$(inherited)`，追加 `$(SRCROOT)/<SDK相对路径>` |
| LD_RUNPATH_SEARCH_PATHS | 保留原值，追加 `$(inherited)`、`@executable_path/Frameworks`、`@loader_path/Frameworks` |

额外字符串 / 数组覆盖只作用于明确的 key 和范围；数组追加保持原值、继承和顺序并去重。不要让新增搜索路径覆盖引擎 / Unity / 团结原有路径。

### 最低版本和 Cocos 引擎

- 将已确定的最低版本写入主工程及递归引用子工程的所有 iOS target 的全部配置；项目配置原本定义 IPHONEOS_DEPLOYMENT_TARGET 时同步。先备份所有相关工程。
- 结合 target 的 SDKROOT、SUPPORTED_PLATFORMS、目标产品类型和继承配置判断平台，不触及 macOS / tvOS / watchOS / visionOS。
- 对 iOS 引擎 target（名称以 cocos_engine、libcocos2d、cocos2d 开头，含子工程），给 OTHER_CPLUSPLUSFLAGS 追加 `-Wno-invalid-specialization` 并保留已有值，兼容原接入行为。不修改引擎 half.h 等源码。

## 递归导入 SDK

建立 SDK 文件清单，识别包容器后停止深入其内部添加引用。

| 类型 | 工程处理 |
|---|---|
| .framework | 整包引用（wrapper.framework），链接到应使用它的 target；动态 framework 还需 App Embed & Sign，见下文 |
| .bundle | 整包引用（wrapper.plug-in），加入主 App Resources |
| .m/.mm/.c/.cc/.cpp/.cxx/.swift | 加入主 target Sources；SDKMessager 和启动源文件有专门规则 |
| .h/.hh/.hpp/.hxx/.pch | 引用，不加入 Sources / Resources |
| .entitlements | 引用，不作为资源打包 |
| .xcassets/.storyboard/.lproj/.xcdatamodeld | 保持容器结构，复用工程对应 file/variant/version group 形式，不把内部文件重复编译或打包 |
| 其他普通资源 | 引用并加入主 App Resources |
| Info.plist、.DS_Store、任意 .dSYM 目录 | 不作为普通资源导入 |

包内的 framework 头文件和资源不单独挂载。跳过 AppDelegate.mm、AppController.mm、UnityAppController.mm、TuanjieAppController.mm 的自动编译挂载；保留工程原有启动源文件。

### Framework 链接和嵌入

- 链接：PBXFrameworksBuildPhase → PBXBuildFile → framework 引用。
- 动态 framework 嵌入：主 App 的 PBXCopyFilesBuildPhase，`dstSubfolderSpec = 10`（Frameworks），对应 PBXBuildFile.settings.ATTRIBUTES 包含 CodeSignOnCopy、RemoveHeadersOnCopy。复用已有 Embed Frameworks 阶段，不创建重复副本。
- 通过 framework 的 Info.plist 中 CFBundleExecutable 定位二进制，用系统 `file` / `otool -hv` 判断动态还是静态；静态 framework 只链接，不嵌入。不能判断时返回问题，不把全部 framework 一律嵌入。这个判断纠正旧脚本一律 Embed & Sign 的行为，保持可运行的接入目的。
- 不改变供应商二进制或其 Info.plist，不在 SDK 目录内签名。嵌入后的签名由 Xcode 构建阶段处理。

## Info.plist、Bundle ID 和 entitlements

- 用 `plutil -p` / `plutil -extract ...` 读取 plist，SDK 原文件保持只读。
- INFOPLIST_FILE 候选为 SDK 内与 framework/bundle 同级的 Info.plist，优先 SDK 根目录；不要误选 framework 内部的 Info.plist。多个非根候选且无法确定时询问。
- INFOPLIST_FILE 使用相对工程路径。若工程开启自动生成 plist，检查 GENERATE_INFOPLIST_FILE 并让其与显式 plist 一致，避免重复生成；不丢失用户明确需要的 target plist 配置。
- 从 SDK 根目录按 CFBundleIdentifier、bundleid、bundleId 顺序取具体 Bundle ID；空值或含 `$(...)` 变量时保留原 Bundle ID 并记录跳过。Unity / 团结作用于已确定的主 App target（通常 Unity-iPhone / Tuanjie-iPhone），不写入引擎 framework、Tests 或 GameAssembly。
- 根目录有 sdk.entitlements 时设置 CODE_SIGN_ENTITLEMENTS；没有则保留原配置。

## SDKMessager、Unity 和团结引擎（Tuanjie）

SDK 根目录优先查找 SDKMessager.mm，否则递归查找；多个不同候选不能确定时返回候选。

### 识别主 App 与引擎 framework

| 导出类型 | 常见主 App target | 常见引擎 framework target |
|---|---|---|
| Unity | Unity-iPhone | UnityFramework |
| 团结引擎（Tuanjie） | Tuanjie-iPhone | TuanjieFramework |

名称是识别线索，最终按 productType、iOS 平台、主 App 的 target dependencies 和产品引用确认配对。不得将团结工程中的 Unity 前缀源文件当作选择 UnityFramework 的依据，也不重命名团结 target、源文件或产品。

- 排除 Tests / UI Tests、GameAssembly 等非主 App target。GameAssembly 保持原有编译和链接关系，不把 AppSDK 或 SDKMessager 挂到它上面。
- 改过名称或混用前缀时，沿已选主 App 的依赖及 productReference 解析实际引擎 framework，不按模板强造缺失 target。
- UnityFramework 和 TuanjieFramework 同时存在时，使用主 App 可唯一确定的配对；无法确定则返回候选询问，不同时挂到两者。
- 工程结构表明属于 Unity / 团结但找不到应有的引擎 framework 时，停止报告缺失，不误走 Cocos 单 target 分支。只有确认无双 target 结构的普通工程才将 SDKMessager 挂到主 target。

### 配置和验证

- 非 Unity / 团结双 target 工程：SDKMessager.mm 仅挂到选定主 target 的 Sources。
- 双 target 工程：AppSDK.framework 链接到确认的引擎 framework target，SDKMessager.mm 编译到该 target；从主 App 移除本次 SDKMessager 的错误重复编译引用。
- 引擎 framework target 搜索路径保留原值并追加 SDK 路径，最低 iOS 版本同步。
- 主 App 对动态 AppSDK.framework 配置 Embed & Sign，并保留 / 补齐主 App 链接关系；静态包不嵌入。不在引擎 framework 内再次嵌套 AppSDK。
- 主 App 链接引擎 framework target 的实际 productReference（例如 BUILT_PRODUCTS_DIR 下的 UnityFramework.framework / TuanjieFramework.framework），不误指向 SDK 同名磁盘文件。核对主 App 对引擎产品已有的 Embed Frameworks 和 target dependency；缺失时按实际产品关系补齐，不能重复或删除其他导出依赖。
- 团结示例：TuanjieFramework 链接 AppSDK 并编译 SDKMessager，Tuanjie-iPhone 嵌入动态 AppSDK 并链接 TuanjieFramework；Bundle ID / Info.plist / AppIcon / 启动图 / entitlements 设置在 Tuanjie-iPhone，Tests 与 GameAssembly 不参与接入。
- 其他 SDK 源码沿用主 target 挂载；除上述 AppSDK / SDKMessager 外，不擅自重分配 target。
- 缺少必要 AppSDK / SDKMessager 文件时报告缺失，不生成替代 SDK 文件。不修改启动源码、不添加初始化代码，包括实际名为 UnityAppController.mm、TuanjieAppController.mm 的启动源文件。
- 构建使用与所选主 App 对应的实际 scheme；团结通常是 Tuanjie-iPhone，不能硬编码 Unity-iPhone。以 xcodebuild -list 返回及依赖图为准。

## AppIcon：只替换图标集

1. 优先 SDK 根目录 1024.png，否则递归查找；多张不同候选不明确时询问。用 `sips -g pixelWidth -g pixelHeight` 确认 1024×1024。没有图片则保留图标，不做删除。尺寸不符时报告，不暗中拉伸。
2. 根据所选 target 的 ASSETCATALOG_COMPILER_APPICON_NAME 和关联资产目录定位正在使用的 AppIcon 集；优先沿用现有命名和目录。多个候选返回选择，不按字母序随便替换。
3. 备份仅将替换的 `<名称>.appiconset` 及工程文件。保留 Images.xcassets、其中其他 imageset / colorset 和目录级 Contents.json；共享图标集会影响其他 target 时先确定范围，必要时为该 target 创建独立图标集。
4. 没有图标集时，在适合该 target 的现有资产目录创建 AppIcon.appiconset；没有资产目录时创建 Assets.xcassets，根 Contents.json 使用 `{"info":{"author":"xcode","version":1}}`，并将该目录挂到主 App Resources。
5. 优先沿用有效 Contents.json 中的 idiom、size、scale 及 appearance 等条目，按 size×scale 算像素。缺文件名的有效图标槽补上文件名。同名文件对应不同尺寸时改为不同文件名，避免覆盖；文件名不可越出图标集目录。1024 通用槽可以复用同一输入图像，不强行改成旧式槽位。
6. 没有有效模板时生成以下规格的 images 条目，info 使用 author=xcode、version=1：

| idiom | size | scale |
|---|---|---|
| iphone | 20×20、29×29、40×40、60×60 | 每种 2x、3x |
| ipad | 20×20、29×29、40×40、76×76 | 每种 1x、2x |
| ipad | 83.5×83.5 | 2x |
| ios-marketing | 1024×1024 | 1x |

7. 使用 `sips -z <像素> <像素> "<源1024.png>" --out "<图标路径>"`，源图不改。每条有效槽应有对应 PNG；同尺寸可复用文件，核对 JSON 和实际像素。只清理本次被替换图标集中的过时图标，不能删除其父资产目录或其他图标集。
8. 设置 target 的 ASSETCATALOG_COMPILER_APPICON_NAME 为实际图标集名称；资源引用存在则复用，不重复添加。检查其他资产在操作前后保持不变。图标编译错误不可用删除整个 Images.xcassets 解决。

## LaunchScreen

- SDK 根目录优先查找 LaunchScreen.storyboard，否则递归查找；同目录可有 LaunchScreenBackground.png。无 storyboard 时保留原启动图。
- 添加对应工程引用和主 target Resources，设置 ASSETCATALOG_COMPILER_LAUNCHSTORYBOARD_NAME、INFOPLIST_KEY_UILaunchStoryboardName 为不带扩展名的名称，检查显式 plist 中启动图设置与最终构建值一致。
- 移除主 target 上指向其他路径的同名启动 storyboard / 背景的旧 Resources 挂载。其他 target 仍使用的共享引用保留，无入边的旧对象可清理；不删除原磁盘资源。
- 不编辑 SDK storyboard 或 SDK plist；如确需修改供应商文件或启动源码，停止并报告。

## 可选 Cocos 2.x 蓝色资源文件夹同步

仅用户要求此项（原 --Asset 能力）时执行：

- 根据工程现有 hortor 引用和实际路径定位包含 jsb-adapter、assets、src、hortor 的共同父目录，多个候选需确定。
- 优先挂到主 target 的 Resources 分组；若改变 group.path 会影响其他子项，保留该分组路径，改用独立子组或正确的相对引用。
- 将存在的上述目录设为 PBXFileReference，lastKnownFileType=folder（蓝色文件夹），加入主 App Resources。不删除磁盘目录。
- 清理主 target 对同一资源树的旧黄色分组 / 重复资源挂载，其他 target 使用的引用保留。
- 清理旧 Copy Files 中 dstSubfolderSpec=7 且目标路径或文件路径匹配这些目录的旧资源拷贝。保留 Embed Frameworks、Embed App Extensions；混有无关文件时只移除对应项，不删整阶段。

## 完成核对

- 所有对象 ID 唯一，新增对象的目标存在；从 rootObject / target 出发的关联完整，phase、build file、fileRef 和 group 没有悬空引用。
- 全部新增文件路径能解析到正确文件；build setting 修改覆盖目标的所有构建配置，未波及其他平台。
- 同一 phase 无重复挂载；Unity / 团结 AppSDK / SDKMessager 所属正确，动态包 Embed & Sign 完整。
- 重复接入时复用现有正确对象，设置和路径追加不重复。AppIcon 以外资产未改变。
- 每个修改的工程用 plutil -lint 和 Xcode -list 检查，再按 build-and-fix.md 编译；记录命令、退出码和日志，不以文本看起来正确代替验证。
