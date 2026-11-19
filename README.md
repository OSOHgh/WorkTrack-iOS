# WorkTrack — iOS 27.2.1 个人工作追踪与进展复盘 App

> **专为个人深度工作管理打造 · iOS 26/27 液态玻璃（Liquid Glass）高饱和视觉设计 · 100% 本地隐私存储 · Windows 零成本云编译与自签安装**

---

## 一、项目概览与核心功能

**WorkTrack** 是一款针对 **iOS 27.2.1**（向下兼容 iOS 18.0+）设计的个人工作待办、进展流水追踪、多维定时提醒与周期复盘汇报工具。无需任何后端服务器与付费开发者账号，所有数据与附件 100% 存储在 iPhone 本地沙盒中。

### 核心特性一览

1. **五段式工作状态全生命周期管理**
   - 支持 **待开始（Todo）**、**推进中（In Progress）**、**等待反馈（Waiting）**、**需继续追踪（Follow-Up）**、**已归档（Archived）** 及 **已取消（Cancelled）**。
   - 当任务完成或归档时，弹出 **结果与后续追踪决策面板（Outcome Decision Sheet）**：既可总结最终成果直接归档，也可一键转为「需继续追踪」并立即约定下一次复追时间。
2. **进展时间轴与多媒体附件管理（AttachmentStore）**
   - 每条任务支持按时间轴追加 **进展更新、卡点/阻塞、关键决策、工作结果、复追记录**。
   - 支持从系统相册选取 **图片/截图（PhotosPicker）** 或从系统文件选取 **任意文档附件（PDF、Word、Excel、TXT、压缩包等）**，支持全屏预览、QuickLook 查阅与分享导出。
   - 开启了 iOS 文件共享（`UIFileSharingEnabled` & `LSSupportsOpeningDocumentsInPlace`），可在 iPhone「文件」App 中直接访问管理。
3. **双层智能本地提醒引擎（NotificationManager）**
   - **第一层：日常固定盘点提醒（RoutineReminderRule）**
     - 内置默认 **09:00 早间待办汇总** 与 **18:30 晚间复盘核对**，并支持手动新增/编辑任意自定义时间点与周几重复规则。
   - **第二层：单任务多时间点逾期 & 复追提醒（customFollowUpSchedules）**
     - 支持为单个任务设置截止提醒、复追提醒，以及手动添加任意多个具体日期+时间的「逾期重提 / 复追时间点」。
     - 支持在系统通知横幅上直接长按或下拉执行 **「快速记进展」**、**「延后1小时提醒」**、**「明早09:30继续追踪」** 或 **「标记完成并归档」**。
4. **一键生成周报 / 月报与 JSON 全量备份（ReportGenerator & BackupService）**
   - 自动汇总指定时间窗口（**本周周报** / **上周周报** / **本月月报** / **自定义区间**）内的 **已完成成果、推进中事项、卡点与阻塞记录、待继续追踪事项**，一键生成结构化 Markdown/纯文本汇报并复制或分享。
   - 支持一键导出完整 JSON 备份包，随时恢复或迁移数据（在 7 天自签重装或换机时零数据丢失）。
5. **iOS 27.2.1 液态玻璃（Liquid Glass）高饱和标签设计**
   - 采用 `.ultraThinMaterial` 半透明毛玻璃卡片、微光高光描边、8 种高饱和度活力分类色（珊瑚橘、琥珀黄、薄荷绿、晴空蓝、靛青蓝、薰衣草紫、玫瑰粉、青碧色），层级清晰、通透灵动。

---

## 二、如何在 Windows 上 0 元云编译生成 `.ipa` 安装包（GitHub Actions）

由于您在 **Windows** 电脑上使用且无需购买 Mac 或 $99/年 Apple 开发者账号，本项目已内置 **GitHub Actions 免费 macOS 云端构建流水线**（[`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml)）与 **XcodeGen 工程配置**（[`project.yml`](project.yml)）。

> **重要省钱提示**：请将代码上传到 **GitHub 公开仓库（Public Repository）**！GitHub 对 Public 仓库提供 **完全免费、不限时长** 的 `macos-latest` 云端构建额度。

### 方法 A：直接通过浏览器网页上传到 GitHub（无需在电脑安装 Git）

如果您电脑上尚未安装 Git，可以直接通过网页端 3 分钟完成上传与编译：

1. 登录 [GitHub](https://github.com/)，点击右上角 **`+`** -> **`New repository`**。
2. 填写仓库名称（例如 `WorkTrack-iOS`），选择 **`Public`（公开）**，勾选 **`Add a README file`**，点击 **`Create repository`**。
3. 进入新建的仓库页面，点击 **`Add file`** -> **`Upload files`**。
4. 打开本项目的文件夹 `c:\Users\38676\Desktop\Agnet工作\APP工作待办`，将里面的所有文件夹与文件（`WorkTrack`、`WorkTrackTests`、`.github`、`project.yml`、`.gitignore`、`README.md`）**直接拖拽到 GitHub 网页上传框中**。
   - *注意：确保 `.github/workflows/ios-build.yml` 也被包含上传。如果网页拖拽未包含隐藏文件夹 `.github`，可点击 `Add file` -> `Create new file`，文件名输入 `.github/workflows/ios-build.yml`，将本地该文件内容粘贴进去即可。*
5. 点击底部的 **`Commit changes`** 提交。

### 方法 B：使用 Git 命令行推送（适合已安装 Git 的环境）

如果您已安装 [Git for Windows](https://git-scm.com/download/win)，可在当前目录打开终端执行：

```powershell
git init
git add .
git commit -m "feat: initial release of WorkTrack for iOS 27.2.1"
git branch -M main
git remote add origin https://github.com/<您的GitHub用户名>/WorkTrack-iOS.git
git push -u origin main
```

### 下载云端编译好的 `WorkTrack-Unsigned.ipa`

1. 代码提交后，点击 GitHub 仓库顶部的 **`Actions`** 标签页。
2. 您会看到 **`Build Unsigned iOS IPA (WorkTrack)`** 工作流正在自动运行（也可以随时点击左侧工作流名称 -> 点击右侧 **`Run workflow`** 手动触发）。
3. 等待约 **2~4 分钟** 构建变成绿色对勾 ✅ 后，点击进入该次构建详情页。
4. 滑动到页面最底部的 **`Artifacts`** 区域，点击下载 **`WorkTrack-Unsigned-IPA`**。
5. 解压下载得到的压缩包，即可获得 **`WorkTrack-Unsigned.ipa`** 免签名安装包！

---

## 三、Windows 0 元自签安装到 iPhone（iOS 27.2.1）完整指南

本项目已专门做过 **免费个人 Apple ID（Personal Team）兼容性优化**：移除了所有需要 $99/年付费账号的特权 Entitlements（如 App Groups、Push Notifications、Critical Alerts），因此使用任何普通免费 Apple ID 均可 **100% 零报错签名安装**。

---

### 前置准备（首次自签必做，仅需一次）

#### 1. 在 Windows 上安装非微软商店版 iTunes 与 iCloud 驱动
- **切勿使用 Microsoft Store 版本的 iTunes/iCloud**（缺少底层 USB 通信驱动）。
- 请下载并安装苹果官方独立安装包（Sideloadly 官网界面也提供官方直链）：
  - [Apple 官方 Win64 iTunes 独立安装包](https://www.apple.com/itunes/download/win64)
  - [Apple 官方 Win64 iCloud 独立安装包](https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe)
- 安装后用数据线将 iPhone 连接电脑，在 iPhone 弹窗上点击 **「信任此电脑」** 并输入锁屏密码。

#### 2. 在 iPhone (iOS 27.2.1) 上开启「开发者模式」与信任证书
1. 首次通过下述工具安装自签应用后，打开 iPhone **「设置」 -> 「通用」 -> 「VPN 与设备管理」**，在「开发者 App」下方点击您的 Apple ID，选择 **「信任」**。
2. 打开 iPhone **「设置」 -> 「隐私与安全性」**，滑动到底部找到 **「开发者模式（Developer Mode）」**：
   - 开启「开发者模式」开关 -> 根据提示点击 **「重新启动」**。
   - 手机重启后屏幕会弹出确认框，点击 **「开启」** 并输入锁屏密码即可。

---

### 方案一：Sideloadly 数据线拖拽安装（最简单稳定，3 分钟上手）

适合平时在电脑旁办公，每 7 天插一次数据线（或同一 Wi-Fi 下自动刷新）的用户：

1. 访问 [Sideloadly 官网 (https://sideloadly.io/)](https://sideloadly.io/) 下载并安装 **Windows 64-bit** 版本。
2. 打开 **Sideloadly**，用 USB 数据线连接您的 iPhone（确保 `iDevice` 一栏显示出您的 iPhone 型号与 iOS 27.2.1 版本）。
3. 在 `Apple account` 输入框中填入您的 **普通免费 Apple ID 邮箱**（也可注册一个全新小号专门用于自签）。
4. 点击左上角的 **`IPA`** 图标（或直接将解压出来的 **`WorkTrack-Unsigned.ipa`** 拖入 Sideloadly 窗口）。
5. 点击底部的 **`Start`** 按钮：
   - 首次使用会提示输入 Apple ID 密码及手机收到的双重认证验证码（6 位数字）。
   - Sideloadly 会自动向苹果服务器申请 7 天免费个人开发证书、完成签名并将 **WorkTrack** 安装到您的 iPhone 桌面！
6. **每 7 天续期技巧**：
   - 免费个人证书有效期为 7 天。到期前只需把手机连上电脑再次点 `Start` 覆盖安装，**只要不卸载桌面上的 App，里面的所有任务、进展记录与图片附件 100% 保留不会丢失！**
   - 您也可以在 Sideloadly 右下角托盘图标开启 `Wi-Fi Sideloading`，当电脑与手机在同一局域网时会自动静默续签。

---

### 方案二：SideStore + iloader 手机端无线自签与自动续期（进阶推荐）

如果您希望安装一次后 **完全脱离电脑**，直接在 iPhone 上随时无线刷新 7 天有效期，推荐使用 **SideStore**：

1. **首次电脑端引导安装 SideStore**：
   - 在 Windows 上下载新一代一键引导工具 **`iloader`**（或使用 `AltServer` + `JitterbugPair`），配合 WireGuard VPN 配置文件（`StosVPN` / `SideStore WireGuard` 配置）。
   - 使用数据线连接 iPhone，通过 `iloader` 将 `SideStore.ipa` 安装到手机并导入配对文件（Pairing File）。
2. **在 iPhone 上导入并自动续期 WorkTrack**：
   - 将 GitHub Actions 下载的 **`WorkTrack-Unsigned.ipa`** 通过微信文件传输助手、AirDrop 或 iCloud 云盘保存到 iPhone 的 **「文件」App** 中。
   - 打开手机上的 **SideStore**（确保已开启配套的本地 Loopback VPN），切换到 **`My Apps`** 标签页，点击左上角 **`+`** 号，选择刚才保存的 `WorkTrack-Unsigned.ipa` 即可直接在手机上完成签名与安装！
   - 以后只需在手机上打开 SideStore 点击 **`Refresh All`**，即可在几秒钟内无线重置 7 天倒计时，无需再开电脑。

---

## 四、项目工程目录结构

```text
WorkTrack/
├── project.yml                         # XcodeGen 工程配置文件 (iOS 18.0+ / iOS 27.2.1 兼容)
├── .github/workflows/ios-build.yml     # GitHub Actions 免费云端编译与 Release 发布流水线
├── WorkTrack/
│   ├── Info.plist                      # iOS 应用配置与相册/文件共享权限声明
│   ├── WorkTrackApp.swift              # App 入口、SwiftData 容器初始化與通知代理挂载
│   ├── Assets.xcassets/                # 应用图标与主题强调色资源目录
│   ├── Models/
│   │   ├── TaskEnums.swift             # 任务状态、优先级、8 色高饱和标签、提醒类型枚举
│   │   └── WorkModels.swift            # SwiftData 模型 (WorkTask, ProgressLog, RoutineReminderRule)
│   ├── Services/
│   │   ├── AttachmentStore.swift       # 本地图片与任意文件附件沙盒持久化管理
│   │   ├── NotificationManager.swift   # 日常固定盘点 + 单任务逾期/复追多时间点通知引擎
│   │   ├── ReportGenerator.swift       # 周报 / 月报结构化复盘文本自动生成器
│   │   └── BackupService.swift         # 全量数据 JSON 导出与恢复服务
│   ├── Theme/
│   │   └── LiquidGlassTheme.swift      # iOS 27.2.1 液态玻璃材质、高光描边与高饱和色彩系统
│   └── Views/
│       ├── MainTabView.swift           # 底部四大主导航标签页与全局快速新建入口
│       ├── FocusDashboardView.swift    # 「今日聚焦」看板：逾期复追预警、今日待办与进行中卡片
│       ├── TaskBoardView.swift         # 「全部工作」多维筛选、搜索与液态玻璃任务列表
│       ├── TaskDetailView.swift        # 任务详情、子步骤勾选、进展时间轴、附件预览与复追排期
│       ├── TaskEditorSheet.swift       # 新建/编辑任务表单（支持自定义分类、色彩与复追提醒时间）
│       ├── OutcomeDecisionSheet.swift  # 完成/归档时的成果总结与「是否继续追踪」分流弹窗
│       ├── ArchiveAndReportView.swift  # 「归档与周月报」生成器与历史成果库
│       └── ReminderSettingsView.swift  # 「提醒与数据」：早晚盘点提醒配置与 JSON 备份恢复
└── WorkTrackTests/
    └── WorkTrackDomainTests.swift      # 核心模型、汇报生成与备份恢复单元测试
```
