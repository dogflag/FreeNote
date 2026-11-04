# FreeNote 第一版实施状态

## 已完成

- iPadOS 16 SwiftUI 应用骨架。
- 笔记：创建、搜索、筛选、重命名、删除、批量删除。
- 分页本 / 无限画布、纸张模板。
- PencilKit 书写、钢笔、荧光笔、橡皮、套索、撤销/重做、颜色/粗细。
- 页面增加、删除、切换、按页保存手写数据。
- 书架和资源库：导入、筛选、网格/列表、预览、删除、资源转书架。
- 当前笔记页附件栏：打开和移除附件。
- PDF 单页阅读、文本模式、PencilKit 批注模式、按页批注保存、阅读进度。
- EPUB、Office 等 QuickLook 预览。
- 独立文档大纲树：任意层级、连续页码范围、自动目录提取和按页 fallback。
- 统一右下角大纲把手：可见、离底边足够远、仅响应手指、点击/上划打开。
- 亮色、暗色、跟随系统、字体与纸张设置。
- 原子持久化、安全作用域处理、ZIP 路径/大小保护、保存失败保护。
- XcodeGen 工程配置、macOS CI 未签名 IPA 构建脚本、单元测试。

## 已通过

- Swift 语法树解析：0 个语法错误。
- project.yml / GitHub Actions YAML 校验。
- Info.plist XML 和 Asset JSON 校验。
- 前端 Store 调用与后端公开方法静态一致性检查。
- 独立代码审查 Agent 两轮回归审查：无已知静态阻断项。

## 尚未验证 / 未实现

- 尚未执行 Xcode 编译和 XCTest。
- 尚未生成真实未签名 IPA。
- 尚未在 iPad + TrollStore 上安装运行。
- PDF 插入空白页、裁剪和永久写回尚未实现；当前仅提供留白预览。
- EPUB 自动页码依赖 spine 顺序，重排后需要重新映射自动大纲。
- Word/PPT（非 PPTX）只做系统预览与保守大纲 fallback。

## 下一步

1. 将仓库放到 GitHub，触发 macOS Actions 构建；或使用任意 macOS + Xcode 环境。
2. 修复首次真实编译产生的错误。
3. 下载 `FreeNote-unsigned.ipa`。
4. 在 iPad TrollStore 安装并做基础验收。
