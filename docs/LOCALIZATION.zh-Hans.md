# CocoaTop 原生汉化

维护者：crctdd。保留原项目版本、标识符与原作者版权。

## 接入方式

CTLocalization.h/.m 提供显式 CTLocalizedString。仅系统首选语言为 zh-Hans、zh-CN、zh-SG 或 zh 时读取 zh-Hans.lproj；zh-Hant 与其他语言原样返回英文。缺少资源或键时同样回退英文。无注入、无 UIKit swizzle。语言变更后重新启动应用。

PSColumn 构造函数统一本地化 name/fullname/descr；Column_ios.h、Column_simulator.h 的静态定义不包裹函数调用，仅运行时 summary block 本地化进程计数格式。详情名称、列说明、设置、预设、菜单、搜索提示、状态汇总与确认按钮使用显式接入。技术缩写（PID、Mach、BSD、TTY、状态字符等）保留。进程名、路径、用户名、套接字动态值与日志不翻译。

Setup 选项数组、FirstColumnStyle、默认注册值和所有业务键保留英文；选择列表通过原始数组下标读写，勾选比较原始值，仅 label 文本本地化。预设字典键与排序规则不变，仅显示 presetNames 的本地化值。UI 中 standardUserDefaults 均替换为 CTPreferences 后端（由兼容模块维护）。

## 资源与来源

translation-rules.json 为 analysis/translations.json 的逐字节副本：225 条、222 个不同原文；保留 ID、地址、顺序、重复和原译。运行时 Localizable.strings 重复按首条取值。translation-overrides.json 独立记录人工纠错；translation-supplements.json 独立记录补充，不伪装为提取词条。源码空白/标点和长段拼接差异在生成阶段适配为精确完整键，运行时不做子串替换或模糊翻译，保留换行和格式占位符。

## 显式纠错

- 原文：Only columns that fit will actually be shown
  - 提取原译：只有已加入的列才会显示出来-------来了老弟-汉化
  - 实际显示：仅显示当前屏幕宽度能够容纳的列
- 原文：This always grows upwards. Kernel is always pid 0, launchd is pid 1.
  - 提取原译：内核总是pid 0，launchd是pid 1。
  - 实际显示：此编号递增。内核的 PID 始终为 0，launchd 的 PID 为 1。
- 原文：Unique ID of process' parent - the one that called exec()/fork().
  - 提取原译：进程父进程的唯一ID，即调用exec（）/fock（）的进程。
  - 实际显示：父进程的唯一 ID，即调用 exec()/fork() 的进程。
- 原文：Summary of this column denotes the number of processes executing as user (aka 'mobile').
  - 提取原译：此列的摘要表示以用户身份执行的进程数（也称为“移动”）。
  - 实际显示：此列汇总以 mobile 用户身份运行的进程数。
- 原文：CPU usage is expressed in % per CPU core, thus it sums up to cores×100%. Sometimes it can even exceed this value, due to reasons explained in this app's 'About' section. This is hilarious!
  - 提取原译：CPU使用率以每个CPU核心的%表示，因此它总计为核心x100%有时甚至会超过这个值，这是由于该应用程序的“关于”部分中解释的原因。
  - 实际显示：CPU 使用率以每个 CPU 核心的百分比表示，因此合计可达核心数 × 100%。有时甚至会超过此值，原因见本应用的“关于”部分。这很有趣！
- 原文：This value is inaccurate due to the fact that CocoaTop can only monitor process' sockets while it is active. Sockets having a lifetime during CocoaTop being inactive are not counted.
  - 提取原译：此值不准确，因为CocoaTop只能在进程的套接字处于活动状态时监视进程的套接字。在CocoaTop处于非活动状态期间具有生存期的套接字不计算在内。
  - 实际显示：此值并不精确，因为 CocoaTop 只能在自身运行时监控进程的套接字。在 CocoaTop 未运行期间创建并关闭的套接字不会计入。
- 原文：Total Mach messages sent by the process.
  - 提取原译：进程发送的Mach数消息总数。
  - 实际显示：进程发送的 Mach 消息总数。
- 原文：Total Mach messages received by the process.
  - 提取原译：进程接收的Mach数消息总数。
  - 实际显示：进程接收的 Mach 消息总数。
- 原文：Process group id.
  - 提取原译：进程组id。
  - 实际显示：进程组 ID。
- 原文：Time elapsed since process launch.
  - 提取原译：进程启动后经过的时间。
  - 实际显示：自进程启动以来经过的时间。
- 原文：Has started profiling
  - 提取原译：已开始性能分析
  - 实际显示：已启动性能分析
- 原文：Selecting; wakeup/waiting danger
  - 提取原译：正在选择；唤醒/等待存在风险
  - 实际显示：正在选择；存在唤醒/等待风险
- 原文：Process was stopped and continued
  - 提取原译：进程已停止并继续
  - 实际显示：进程曾停止后又继续
- 原文：Timing out during sleep
  - 提取原译：在休眠期间超时
  - 实际显示：休眠期间超时
- 原文：Debugged process being traced
  - 提取原译：被追踪的调试进程
  - 实际显示：调试进程正在被跟踪
- 原文：Application is suspended by SpringBoard (iOS specific)
  - 提取原译：应用程序被 SpringBoard 暂停(iOS 特定)
  - 实际显示：应用已被 SpringBoard 挂起（仅限 iOS）
- 原文：Debugged process is being traced
  - 提取原译：正在跟踪调试过程
  - 实际显示：调试进程正在被跟踪
- 原文：Not nice: higher priority
  - 提取原译：不好：优先级更高
  - 实际显示：更高优先级
- 原文：Nice: lower priority, also see 'Nice' column
  - 提取原译：Nice：优先级较低，另请参阅“Nice”栏
  - 实际显示：较低优先级，另请参阅“Nice”列

## 静态覆盖统计

运行 `python3 scripts/audit-localization.py` 可重现并更新 `docs/localization-audit.json`。当前结果：

- 完整原始规则 225 条、222 个不同原文，资源与恢复 JSON 字节一致。
- 实际精确键 388 个：222 个提取原文基础键、19 个显式纠错覆盖、132 个独立补充键、34 个源码差异适配键（这些分类会有覆盖，不能简单相加）。
- 去除注释后，显式字面量调用 48 处、38 个不同键，全部存在于资源且 printf 格式标记序列一致。
- iOS 列模型 52 个完整名称、44 段说明全部有精确中文键；模拟器对应 52/44 同样覆盖；详情列另有 19 个完整名称全部覆盖。
- 三个模型文件合计 318 个非空显示字段出现位置，287 个命中中文键；176 个不同非空显示原文中 159 个有中文键。未命中的 17 个不同字段仅为刻意保留的技术符号/缩写（PID、PPID、%、S、TTY、Mach、BSD、CSw、Nice、TID、Pri、FD、F、R、ΣMach、ΣBSD、ΣCSw），不能将其称为 100% 全文字汉化。
- iOS/模拟器共 88 段长说明逐一验证换行数不变。所有本工作涉及 UI 文件的业务键、chooseFrom 原始数组、FirstColumnStyle 默认值与选择保存逻辑均通过静态断言。
- 38 处 UI/列模型默认配置调用改用 CTPreferences；此统计不包含兼容模块负责的文件。
- 222 个恢复原文中，93 个与当前显示源码字面量完整匹配，197 个可在源码字面量中按大小写/空白归一化后找到子串。后者只是来源适配线索，不等于 197 个运行时独立调用；未出现的提取条目仍保留在资源中，不虚报应用功能。
- `git diff --check` 通过。本审计不等于 Objective-C 编译或设备运行验证。

## 未覆盖区域与验证边界

- res/guide.html 与 res/story.html 正文未汉化，仍显示原始英文；导航标题已汉化。LaunchScreen.storyboard 未修改。
- 来自内核、文件描述符、Mach 端口、网络协议的动态状态和技术诊断字符串保留原文，不对动态数据盲目查词。
- 原词库中 NewTerm/语言/触觉等与本版本无关的条目保留为证据和词条，不代表应用新增了这些功能。
- 本工作仅静态检查，未本机编译、未安装、未实机验证。资源打包和 Xcode/Theos 引用由构建模块接入；必须确保 CTLocalization.m 参与编译且 .lproj 整目录进入 App。
- 设备回归需检查：中文列宽/截断、设置选择并重启仍保留原值、恢复默认、线程/文件/端口/模块菜单、长段说明、英文与繁体回退、rootless/roothide 资源路径。
