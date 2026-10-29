# CocoaTop 接管与兼容性审计

基线：crctdd/CocoaTop，提交 bf193b85cf217b5b4e4823e20dd22aba3abaacd5（TrollStore 分支）。本次维护者：crctdd。保留 GPL-3 及原有版权；汉化基础来源：来了老弟的 cn.llld.cocoatop 0.0.3。

## 范围

- 独立 UIKit 进程查看应用，不向 SpringBoard / 系统服务注入 dylib，不安装守护进程。
- 版本沿用已有发行版本 3.0.0，应用及 Debian 包标识 com.crctdd.cocoatop，显示名 CocoaTop。
- 目标 iOS 15–17 的 rootless 和 roothide 越狱环境，不是 TrollStore IPA 或普通 App Store 应用。
- 原生简体中文界面；系统非简体中文回退英文。HTML 帮助及历史故事正文仍为英文。

## 高权限组件与限制

原代码采用 persona 提权启动内嵌助手。此次从 RootWrapper.c 在 CI 构建助手，安装为 root:wheel / 4755，GUI 保持 0755。助手只允许读取进程列表，不执行任意 shell 命令。启动校验 owner / mode，并以 READY 握手验证有效 root 权限；部署时必须确认越狱环境实际允许 setuid 与对应签名。

新增串行通信、响应超时、共享内存名称传递、长度及所有者校验、独立拥有的进程快照，避免负数计数、失效映射和未终止日志缓冲区。应用启动失败不再静默挂起，而是显示诊断。

**仍需设备验证的权限边界**：GUI 的 SIGTERM / SIGKILL 仍由原有 kill() 路径发出，mobile 身份对其他 UID 的进程操作可能失败；不能把 root 列表助手描述为完整 root RPC。task_for_pid、线程、网络统计等细节也受越狱补丁、entitlement 和系统版本限制。未擅自把整个 GUI 设为 root。

## 配置与数据

使用显式 CTPreferences 存储，rootless 写 /var/jb/var/mobile/Library/Preferences/com.crctdd.cocoatop.plist；roothide 使用 jbroot 动态路径。解析失败不回退原生 Preferences。原子写入、文件锁、缓存与失败保留 pending 修改；不自动迁移或删除旧应用数据。

## 网络与安装

本地审查的应用路径未发现进程数据上传 / 遥测实现。CI 下载锁定版本的构建依赖，与运行时网络行为无关。原仓库预编译助手不参与打包，CI 必须构建源码版本。未在当前手机安装、注销或重启。具体安装脚本与包结构以构建文档及 verify-package.py 检查为准。

## 验证口径

静态审计不是设备兼容证明；GitHub Actions 编译通过也不能代替 iOS 15/16/17 真机功能回归。包验证应检查标识、版本、冲突、安装路径、owner/mode、架构、签名及中文资源。实际 CI 结果和产物由本次交付说明记录。
