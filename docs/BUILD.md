# CocoaTop 双环境构建与审计

## 使用方式

GitHub Actions 的 `Build CocoaTop` 工作流支持 push 到 main/master，以及 `workflow_dispatch` 选择 all/rootless/roothide。仅在 CI 编译；配置本身不会安装到手机。

统一入口为 `bash scripts/build.sh rootless`、`bash scripts/build.sh roothide` 或 `bash scripts/build.sh all`。本地如需使用入口，自行配置 `THEOS_ROOTLESS` 和 `THEOS_ROOTHIDE`，GNU make 可通过 `MAKE_BIN` 指定。all 顺序启动两个独立进程，每个环境先 clean 再 package；一个失败仍尝试另一个，最终任一个失败则非零退出。单次产生的 deb 必须通过验证才复制至 `dist/rootless/` 或 `dist/roothide/`，目录另含日志、SHA256SUMS、验证报告；CI 另存 toolchain.txt。

rootless 为 arm64+arm64e，包架构 iphoneos-arm64；roothide 为 arm64e，包架构 iphoneos-arm64e。部署版本 15.0，编译 SDK 为官方 theos/sdks 的 iPhoneOS16.5.sdk。现代 arm64e ABI 面向 iOS14+，不尝试支持旧版 arm64e ABI。

## 固定依赖与工具链记录

2026-10-30 经 GitHub API 核验的提交：

- theos/theos: `6e7b8c40e0f5f9f5b2377800dc1e42cd2560d24a`
- roothide/theos: `3ac89c984ec652fd16bcd91b33ae16de45ce76fa`
- theos/sdks: `0222fd5413cf4b9af096f37b4621afa2688572f7`
- actions/checkout v4: `11d5960a326750d5838078e36cf38b85af677262`
- actions/upload-artifact v4: `ea165f8d65b6e75b540449e92b4886f43607fa02`

SDK 仅 sparse checkout 16.5 目录，Theos 子模块递归按 gitlink 固定。不下载并执行远程安装脚本、不恢复旧全局缓存。macos-15 runner 默认 Xcode/Apple Clang 和 Homebrew make/ldid/dpkg 的确切版本记录到产物；没有证据保证托管 runner 提供 Xcode27，因此不宣称使用 Xcode27/Clang21。升级固定提交需独立审查并跑 CI。

## 原生 Theos 构建链

主链不再调用 xcodeproj.mk，避免过期工程、架构及工程格式影响发布。`src/*.m` 全部自动纳入（含 CTLocalization、CTPreferences），资源使用 Theos 的 `RESOURCE_FILES`，其中 lproj 目录通过 rsync 原样复制，JSON 规则同样进入 app。LaunchScreen 和 Assets 由 Apple ibtool/actool 编译，图标清单合入 Info.plist。资源内旧预编译 CocoaTop-helper 明确排除，助手必须由本次源码生成。

旧 Xcode 工程只同步了 Bundle ID、版本、最低系统，不作为双环境发布入口；直接 Xcode 构建不能替代 helper 从源码构建、包权限设置和 roothide Theos 处理。

## staging 与权限证据

- theos/theos `makefiles/instance/application.mk` 将应用 stage 到 `$(THEOS_STAGING_DIR)/Applications/CocoaTop.app`。
- `makefiles/instance/shared/bundle.mk` 的 shared-instance-bundle-stage 使用 rsync，无 --delete，目录资源保留自身层级。
- `makefiles/package/deb.mk` 在 internal-package 阶段才整体搬移 stage 内容进入 scheme 前缀。因此 after-stage 必须使用 **没有 /var/jb 前缀** 的路径；不能此时添加 THEOS_PACKAGE_INSTALL_PREFIX。
- rootless deb 最终为 var/jb/Applications/CocoaTop.app；roothide deb 为 Applications/CocoaTop.app，由越狱安装器动态定位 jbroot，禁止硬编码随机目录。
- GUI 为 root:wheel/0755，无 setuid。只有助手为 root:wheel/4755。verify-package.py 对最终 deb 的数字 uid/gid、权限、架构及 ldid entitlements 强制断言，不合格不给出发布包。
- 删除双方 persona-mgmt；助手去掉不使用的 task ports、网络统计、managed configuration、diagnostic、memorystatus、thread state、exception port、sysdiagnose 权限。AppBundles 权限按 roothide/Developer 官方 README 添加。保留必要 no-sandbox/platform/process-info/shared-memory 权限；这仍是高权限软件，必须实机验证。
- 不新增 postinst/prerm，不执行 chmod/chown 设备命令、uicache、注销或重启。应用图标刷新由包管理器处理，若目标包管理器未自动注册，需后续经用户授权验证。

## 元数据与版权

显示名称 CocoaTop，Package/Bundle ID com.crctdd.cocoatop，Author/Maintainer crctdd。沿用上游现有 deb 版本 3.0.0，并将旧 plist 的 1.0 与 Xcode CURRENT_PROJECT_VERSION 统一为 3.0.0；不是新建版本。Conflicts/Replaces 为 cn.zqbb.ccatop、cn.llld.cocoatop、ru.domo.cocoatop64、cn.zqbb.ccatop.whitelist。

保留 LICENSE、源码与资源中的上游版权；维护者身份不代表取代 Domo、SXX 等上游作者。首次 CI 编译和 iOS15/16/17 各环境实测前，不能宣称二进制构建或设备兼容已验证。
