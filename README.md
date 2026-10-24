# Vibe 假期闹钟 (VibeAlarm)

**100% 本地、隐私优先的 iOS 智能节假日与调休闹钟** —— 零后端 API、零集中式 Agent 依赖，数据完全由用户自己掌控。

## 核心特性

1. **三合一本地假期与调休引擎 (`VibeAlarmCore`)**
   - **外部公共假期日历订阅 (`.ics`)**：内置**中国国务院法定节假日与调休补班**、**新加坡 MOM 公共假期**订阅预设，并支持任意自定义 `https://` 或 `webcal://` iCal 链接。自动区分**法定节假日（自动跳过闹钟）**与**周末调休补班（周末自动开启工作日闹钟）**。
   - **读取本地系统日历 (`EventKit`)**：仅在设备本地扫描用户勾选的系统日历，匹配自定义关键词（`请假`、`休假`、`年假`、`病假`、`PTO`、`Leave`、`Vacation`、`Out of Office`），休假期间自动跳过早起闹钟，绝不上传任何日历数据。
   - **BYOK LLM 智能录入 + 零网络离线解析 (`BYOKHolidayService`)**：用户可自带 OpenAI 兼容（OpenAI / DeepSeek / OpenRouter / Ollama）或 Anthropic API Key（仅加密存储于 iOS 系统 `Keychain`）。直接粘贴 HR 放假邮件、政府公告或一句话（如 `"10月26日到28日休年假，10月31日补班"`），即可提取结构化假期写入内置日历，同时自动识别文本中的 `.ics` 订阅链接。即使不配 Key 或断网，也内置本地正则/日期引擎秒级解析。

2. **左右手双转盘交互 (`DualThumbTimeDialView`)**
   - **上半部双拇指滚轮**：左手拇指上下滑动调节 **时 (`00–23`)**，右手拇指上下滑动调节 **分 (`00–59`)**，配 `UIImpactFeedbackGenerator` 刻度震动反馈与 `+5m` / `:00` / `:15` / `:30` / `:45` 快捷分针键。
   - **下半部周期与日期**：支持「智能工作日」「每天」「自定义星期 (`一~日`)」与「指定日期 (`YYYY-MM-DD`)」。

3. **聚焦最近两天 + 一键推迟与次日自动恢复**
   - 主界面与桌面交互式小组件（`WidgetKit` + `AppIntents`）仅清晰展示**今天与明天（最近两天）**的闹钟排期与跳过原因。
   - 桌面小组件直接提供 **「跳过明日」「推迟 +30m」「恢复原定」** 三个交互按钮，无需打开 App 即可一键操作；单次推迟或跳过仅对明天生效，**后天自动恢复原定排期**。
   - **睡前可交互通知**：每晚（默认 `22:30`）推送明日闹钟状态提醒，长按通知即可直接点选跳过、推迟或强制保持。

## 目录结构

```text
├── project.yml                  # XcodeGen 工程配置 (VibeAlarm App + VibeAlarmWidget Extension)
├── VibeAlarmCore/               # 纯 Swift 核心包 (可独立运行单元测试)
│   ├── Package.swift
│   ├── Sources/VibeAlarmCore/
│   │   ├── Models.swift                 # 闹钟规则、次日覆盖、假期条目与订阅模型
│   │   ├── AlarmScheduleEngine.swift    # 最近两天及未来 7 天节假日/调休/请假排期计算引擎
│   │   ├── ICSHolidayParser.swift       # RFC 5545 .ics 日历解析与放假/调休补班分类器
│   │   ├── BYOKHolidayService.swift     # BYOK LLM 直连提取 + 本地离线自然语言日期解析
│   │   └── SharedAlarmStore.swift       # App Group 原子 JSON 存储与次日覆盖自动过期
│   └── Tests/VibeAlarmCoreTests/
│       └── VibeAlarmCoreTests.swift     # 完整单元测试套件
├── iOS/
│   ├── Shared/
│   │   ├── AppConstants.swift           # App Group / Keychain / Notification 常量
│   │   ├── AlarmNotificationScheduler.swift # 睡前提醒与多段 Time-Sensitive 闹钟通知调度
│   │   └── AlarmAppIntents.swift        # Widget 交互按钮与快捷指令 (AppIntents)
│   ├── App/
│   │   ├── VibeAlarmApp.swift           # App 入口与长按通知交互 Delegate
│   │   ├── AppViewModel.swift           # 状态管理与本地日历/ICS 同步协调
│   │   ├── TwoDayDashboardView.swift    # 最近两天闹钟主看板
│   │   ├── DualThumbTimeDialView.swift  # 左右手双转盘设定组件
│   │   ├── BYOKInputSheet.swift         # BYOK 粘贴邮件/公告录入弹窗
│   │   ├── HolidayCalendarView.swift    # 内置假期日历与外部 ICS 订阅管理
│   │   ├── SettingsView.swift           # Keychain BYOK 密钥与本地日历隐私设置
│   │   ├── LocalCalendarManager.swift   # EventKit 本地日历请假扫描器
│   │   └── KeychainHelper.swift         # iOS Keychain 安全读写封装
│   └── Widget/
│       └── VibeAlarmWidget.swift        # 桌面最近两天交互式小组件 (SystemSmall / SystemMedium)
└── .github/workflows/
    ├── ci.yml                   # macOS Xcode 自动测试、XcodeGen 生成与未签名 IPA 打包上传
    └── release.yml              # Tag 发布自动构建 IPA 并上传 GitHub Release
```

## 编译与安装

- **GitHub Actions 云端打包（无需本地 Mac）**：每次推送到 `main` 分支，GitHub Actions 会自动运行 `VibeAlarmCore` 单元测试、通过 `xcodegen` 生成 Xcode 工程并编译生成未签名的 `VibeAlarm.ipa` 产物（可在 Actions Run 页面直接下载 `VibeAlarm-unsigned-ipa`，配合 AltStore / Sideloadly / TrollStore 或个人证书签名安装）。
- **本地 Xcode 编译**：
  ```bash
  brew install xcodegen
  xcodegen generate
  open VibeAlarm.xcodeproj
  ```
