# 发布检查清单

## 构建

- `swift build` 通过
- `Scripts/package_app.sh` 能生成 `.app`
- `codesign -dv --verbose=4 build/WallhavenWallpaper.app` 输出正常

## macOS 分发

- 正式 `BUNDLE_ID`
- 正式 App 图标
- Developer ID 签名
- Notarization + staple
- 若走 App Store，补 sandbox entitlements 并验证文件访问策略

## 隐私和审核

- `PrivacyInfo.xcprivacy` 已包含
- API Key 存 Keychain
- NSFW 默认关闭
- NSFW 在线缩略图、本地缩略图和详情图默认模糊
- App Store 年龄分级如实填写
- Review Notes 说明图片来自 Wallhaven，NSFW 需要用户显式开启

## 功能验证

- Latest / Hot / Toplist / Random / Search 能加载
- 翻页正常，Random seed 不重复
- 重复打开同一搜索页优先使用缓存，缩略图不会反复下载
- 设置页可查看和清理缓存
- 下载图片按月/按日保存
- 标签可编辑并可筛选
- 删除已下载文件会移到废纸篓，并移除 SwiftData 记录
- 壁纸墙播放/暂停、随机聚焦、密度调整正常
- NSFW 图片需点眼睛图标才临时显示
- Quick Look、Finder 定位、拖拽可用
- 当前屏幕和全部屏幕壁纸设置可用
- 本地视频动态桌面可启动、停止，低电量模式暂停有效
- 自动换壁纸可按间隔运行，随机/顺序/规则过滤行为符合预期
