# FreeNote Draft

当前目录是 FreeNote 的产品与界面设计稿，暂未开始开发可运行版本。

## 查看顺序

1. `设计思路与功能规划.md`
2. `screenshots/00-design-overview.png`
3. 各单页视觉稿：
   - `screenshots/01-notes-workspace.png`
   - `screenshots/02-bookshelf.png`
   - `screenshots/03-library.png`
   - `screenshots/04-reader-annotation.png`
   - `screenshots/05-dialogs-settings.png`
4. 交互式静态预览：用浏览器打开 `index.html`

## 当前设计范围

- 左侧一级导航：笔记 / 书架 / 资源库
- 笔记工作区、手写工具栏、页面缩略导航
- 书架、资源库、文件分类
- PDF/电子书阅读、手写批注、文本选择、页面留白与插入空白页
- 新建笔记、导入文件、设置弹窗

## 说明

`index.html` 只用于视觉确认，不包含真实手写、文件解析、PencilKit 绘制或数据存储逻辑。确认设计后再进入 iOS 工程和 TrollStore IPA 打包阶段。
