# FreeNote

FreeNote 是一个面向 iPad 的极简手写笔记与阅读器。当前仓库正在实现首个 TrollStore 测试版本。

## 技术基线

- iPadOS 16.0+
- Swift 5.9 / SwiftUI
- PencilKit、PDFKit、QuickLook、ZIPFoundation
- 本地优先存储，无账号依赖
- XcodeGen 生成工程
- GitHub Actions macOS 构建未签名 IPA

## 本地打开工程（macOS）

```bash
brew install xcodegen
xcodegen generate
open FreeNote.xcodeproj
```

选择 `FreeNote` scheme 和 iPad 模拟器运行。

## 构建 TrollStore IPA

在 macOS 上：

```bash
chmod +x scripts/build-ipa.sh
scripts/build-ipa.sh
```

输出：`build/FreeNote-unsigned.ipa`

也可以将仓库推送到 GitHub，在 Actions 中运行 `Build TrollStore IPA`，下载 `FreeNote-unsigned-ipa` artifact。

## 下载测试包

最新预发布版本：https://github.com/dogflag/FreeNote/releases/tag/v0.1.0-alpha.1

## 真机安装

1. 下载 `FreeNote-unsigned.ipa`；
2. 分享或传输到 iPad；
3. 用 TrollStore 打开并安装；
4. 如系统提示不受信任或版本不兼容，记录 iPad 型号、iOS 版本和 TrollStore 版本。

首版不包含正式 Apple 签名、App Store 上架配置或 iCloud 能力。

## 当前进度

- [x] 产品与视觉草案
- [x] 模块边界和公共接口契约
- [x] XcodeGen / GitHub Actions 构建骨架
- [x] 数据层与导入
- [x] 笔记工作区
- [x] 书架、资源库和阅读器
- [x] 大纲功能
- [x] IPA 云构建`n- [ ] TrollStore 真机安装验证

## 文档

- `docs/ARCHITECTURE.md`：模块边界、公共接口、持久化与大纲规则
- `docs/BUILD_AND_TEST.md`：构建、测试与真机验证步骤
- `draft/`：设计稿和功能说明

## 第一版已知限制

- PDF 当前固定单页阅读，缩放/滚动锁定时优先保证手写批注坐标不漂移。
- PDF 的“页面留白”目前是阅读预览；插入空白页、裁剪及写回原 PDF 尚未实现。
- EPUB、PPT、Word 等通过 QuickLook 打开；自动目录识别目前覆盖 PDF、EPUB 和 PPTX，其他 Office 格式使用保守 fallback。
- 尚未在真实 iPad / TrollStore 环境验证。

