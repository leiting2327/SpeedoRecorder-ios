# 车速记录仪 SpeedoRecorder（iOS 17+）

纯黑背景、实时刷新的车速仪表工具，支持把车速 / GPS 信号 / 位置 / 里程等信息实时烧录进行程视频，并导出轨迹数据。

## 已实现功能

### 核心
- **实时车速**：基于 CoreLocation 连续定位回调驱动，位置一更新就刷新，不用固定 1 秒轮询；支持 km/h、mph 切换。
- **GPS 信号强度**：按水平精度换算 0~4 格信号，显示精度米数与信号文案。
- **当前位置与逆地理**：可选 系统地图 / 高德 / 百度 三种数据源；填入对应 Web 服务 Key 后实时解析地址。
- **轨迹数据记录**：逐点记录时间、经纬度、海拔、航向、精度、速度、GPS 档位、累计里程、爬升、活动状态。
- **行程视频录制**：跟随屏幕刷新率实时渲染帧，画面中烧录车速、REC 时长、GPS 信号、地址、经纬度、里程、海拔、航向、爬升、活动状态、最高车速；导出 H.264 MP4 并可保存到相册。
- **数据导出**：CSV（表格可打开）与 JSON（结构化）两种格式，含行程汇总（最高/平均车速、总里程、总爬升、采样点数）。

### 附加功能
- 里程 / 海拔 / 航向 / 累计爬升 / 最高车速 / 出行状态（驾车/骑行/步行/跑步/静止）实时卡片。
- 超速阈值设置 + 超速红色告警。
- 内嵌 Apple 地图预览跟随定位；一键跳转到高德 / 百度 / 系统地图 App。
- 后台定位持续记录轨迹。
- 液态玻璃（UltraThinMaterial）深色卡片界面。

## 地图 Key 配置

- **系统地图**：无需 Key。
- **高德**：开放平台申请「Web 服务」Key，在设置页填入；用于逆地理编码与静态地图。
- **百度**：开放平台申请服务端 AK，在设置页填入；用于逆地理编码与静态地图。

## 构建 IPA（GitHub Actions 自动）

仓库 `.github/workflows/build-ipa.yml` 在 `macos-latest` 上：XcodeGen 生成工程 → 无签名编译 → 打包带版本号的 IPA → 上传 artifact 并发布 Release。

本地 Mac 手动构建：

```bash
brew install xcodegen
cd SpeedoRecorder
xcodegen generate
xcodebuild -project SpeedoRecorder.xcodeproj -scheme SpeedoRecorder \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

未签名 IPA 需用 Sideloadly / AltStore / 爱思助手以自己的 Apple ID 重签名后安装；免费证书签名 7 天后需重签。

## 版本

- 当前：1.0.0（build 1），版本号在 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。
- 每次修改代码后递增版本号，IPA 文件名同步带版本号。
