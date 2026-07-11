# Wallhaven Wallpaper

macOS SwiftUI + SwiftData 壁纸下载工具，支持浏览 Wallhaven 的 Latest、Hot、Toplist、Random 和搜索结果，按日期或月份保存图片，并设置为桌面壁纸。

## 功能

- Wallhaven 分类：Latest、Hot、Toplist、Random、Search
- 筛选：General / Anime / People、SFW / Sketchy / NSFW、排序、分辨率、比例、颜色
- NSFW 保护：在线结果、本地图库和详情预览默认模糊，点眼睛图标临时显示
- 分页：支持上一页、下一页和随机 seed 翻页
- 缓存：搜索结果、在线缩略图和本地图片解码均支持缓存，减少重复请求和流量消耗
- 本地图库：SwiftData 保存元数据，图片保存到本地目录
- 标签：支持给本地图片添加标签并筛选
- 删除：支持把已下载图片移到废纸篓并删除图库记录
- macOS 集成：Quick Look、Finder 定位、拖拽、当前屏/全部屏壁纸设置
- 壁纸墙：基于已下载图片生成动态壁纸墙，支持播放/暂停、随机聚焦和密度调整
- 动态桌面：支持选择本地 `.mp4/.mov` 视频，模拟动态桌面循环播放
- 自动换壁纸：支持定时间隔、随机/顺序/倒序/新旧优先，以及标签、SFW、最低分辨率规则
- 安全：API Key 保存到 Keychain

## 运行

```bash
swift run
```

## 打包

```bash
Scripts/package_app.sh
open build/WallhavenWallpaper.app
```

默认使用 ad-hoc 签名。发布时可传入正式证书：

```bash
APP_IDENTITY="Developer ID Application: Your Name" Scripts/package_app.sh
```

## 说明

NSFW 默认关闭。开启 NSFW 通常需要 Wallhaven API Key；NSFW 图片默认模糊，需要手动点眼睛图标预览。发布到 App Store 前需要认真处理年龄分级、内容来源和审核说明。

缓存默认开启，路径位于用户缓存目录 `~/Library/Caches/WallhavenWallpaper`。设置里可以调整最大容量，或分别清理搜索结果、缩略图缓存。

视频动态桌面使用公开 macOS API 模拟实现：创建不抢焦点、忽略鼠标事件的桌面层窗口，并用 `AVPlayerLayer` 硬件解码循环播放。默认只在当前屏幕启用，低电量模式会暂停，适合低配置电脑。

锁屏播放不能由普通 App 直接替换系统锁屏界面。可行方向是单独开发 `.saver` 屏保插件，读取本 App 下载目录，详见 `Docs/LOCK_SCREEN_SCREENSAVER_STRATEGY.md`。
