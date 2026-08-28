# PulseDock 环境音来源目录

更新日期：2026-08-25

## 收录与核验规则

- 本目录只收录 Freesound 作品页明确标记为 [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) 的录音。
- 24 条记录使用不同的 Freesound sound ID 与 HTTPS 预览 URL；同一录音不会通过改名重复出现。
- 2026-08-25 逐项读取作品页，核对作者、CC0 标记、时长与 Freesound 生成的 HQ MP3 预览地址；随后仅请求每个预览的第一个字节，24 条均返回 HTTP 206 与 `audio/mpeg`，没有下载完整音频。
- `lastVerified` 是核验日期，不是永久可用保证。第三方删除作品、修改预览地址或暂时不可用时，应用应显示来源故障，不得静默切换到来源不明的音频。
- PulseDock 只在用户点击播放后连接预览流，不内置、不预取、不自动播放，也不保存播放历史。CC0 不要求署名，但产品仍保留作者与作品页用于审计。

## 24 条已核验录音

| PulseDock ID | 显示名称 | Freesound 来源与作者 | 时长 | HTTPS 预览 | 分类标签 |
|---|---|---|---:|---|---|
| `rain-window` | 窗边雨声 | [freesound:81818](https://freesound.org/s/81818/) · silencyo | 1:21.835 | [MP3](https://cdn.freesound.org/previews/81/81818_280284-hq.mp3) | rain, indoor, focus |
| `wind` | 旷野微风 | [freesound:217506](https://freesound.org/s/217506/) · felix.blume | 3:32.318 | [MP3](https://cdn.freesound.org/previews/217/217506_1661766-hq.mp3) | wind, nature, focus |
| `leaves` | 林间树叶 | [freesound:457318](https://freesound.org/s/457318/) · Stek59 | 0:42.914 | [MP3](https://cdn.freesound.org/previews/457/457318_9065275-hq.mp3) | forest, leaves, wind, nature |
| `thunder` | 远处雷雨 | [freesound:316831](https://freesound.org/s/316831/) · Boryslaw_Kozielski | 3:07.155 | [MP3](https://cdn.freesound.org/previews/316/316831_2609215-hq.mp3) | rain, thunder, night, nature |
| `underwater` | 水下空间 | [freesound:482167](https://freesound.org/s/482167/) · Tim_Verberne | 2:00.000 | [MP3](https://cdn.freesound.org/previews/482/482167_4838691-hq.mp3) | water, underwater, focus |
| `brown-noise` | 棕色噪音 | [freesound:171552](https://freesound.org/s/171552/) · georgedyer | 60:00.050 | [MP3](https://cdn.freesound.org/previews/171/171552_3195672-hq.mp3) | noise, focus, indoor |
| `ocean-waves` | 禅意海浪 | [freesound:456899](https://freesound.org/s/456899/) · INNORECORDS | 1:35.779 | [MP3](https://cdn.freesound.org/previews/456/456899_9518146-hq.mp3) | water, ocean, waves, nature, focus |
| `cafe-room` | 街角咖啡馆 | [freesound:706805](https://freesound.org/s/706805/) · Vecera_999 | 3:12.000 | [MP3](https://cdn.freesound.org/previews/706/706805_13871294-hq.mp3) | cafe, indoor, city, people |
| `fireplace` | 壁炉柴火 | [freesound:263864](https://freesound.org/s/263864/) · ceich93 | 0:59.961 | [MP3](https://cdn.freesound.org/previews/263/263864_4457609-hq.mp3) | fire, indoor, night, focus |
| `hearth-fire` | 温暖炉火 | [freesound:414767](https://freesound.org/s/414767/) · samarobryn | 1:00.000 | [MP3](https://cdn.freesound.org/previews/414/414767_4955305-hq.mp3) | fire, indoor, night, focus |
| `winter-birds` | 冬日林鸟 | [freesound:723913](https://freesound.org/s/723913/) · Magnesus | 0:27.052 | [MP3](https://cdn.freesound.org/previews/723/723913_2008500-hq.mp3) | forest, birds, nature, morning |
| `forest-creek` | 林间溪流 | [freesound:693851](https://freesound.org/s/693851/) · bumbdoident | 2:48.500 | [MP3](https://cdn.freesound.org/previews/693/693851_12869299-hq.mp3) | water, creek, forest, birds, nature |
| `tram-interior` | 有轨电车车厢 | [freesound:580641](https://freesound.org/s/580641/) · The_Runner_01 | 6:30.838 | [MP3](https://cdn.freesound.org/previews/580/580641_4688703-hq.mp3) | transport, train, indoor, people, city |
| `library-room` | 安静图书馆 | [freesound:408514](https://freesound.org/s/408514/) · PasekaM | 2:32.000 | [MP3](https://cdn.freesound.org/previews/408/408514_7117779-hq.mp3) | library, indoor, focus, people |
| `city-night` | 城市夜色 | [freesound:237329](https://freesound.org/s/237329/) · Soundkrampf | 1:07.717 | [MP3](https://cdn.freesound.org/previews/237/237329_3435865-hq.mp3) | city, night, traffic, outdoor |
| `summer-crickets` | 夏夜虫鸣 | [freesound:436528](https://freesound.org/s/436528/) · KikeVilaplana | 0:51.067 | [MP3](https://cdn.freesound.org/previews/436/436528_8938826-hq.mp3) | insects, crickets, night, nature |
| `typing-room` | 书桌键盘 | [freesound:851269](https://freesound.org/s/851269/) · Sayaka04 | 2:15.321 | [MP3](https://cdn.freesound.org/previews/851/851269_16102858-hq.mp3) | typing, keyboard, indoor, focus |
| `swedish-forest` | 瑞典森林清晨 | [freesound:488328](https://freesound.org/s/488328/) · priesjensen | 6:05.987 | [MP3](https://cdn.freesound.org/previews/488/488328_8972317-hq.mp3) | forest, birds, insects, wind, nature, morning |
| `train-interior` | 列车行进 | [freesound:143205](https://freesound.org/s/143205/) · bisanu6 | 1:26.496 | [MP3](https://cdn.freesound.org/previews/143/143205_2051926-hq.mp3) | transport, train, indoor, focus |
| `cafe-espresso` | 咖啡店早餐 | [freesound:332271](https://freesound.org/s/332271/) · evsecrets | 2:30.584 | [MP3](https://cdn.freesound.org/previews/332/332271_2367065-hq.mp3) | cafe, indoor, city, people |
| `shore-waves` | 海岸浪花 | [freesound:531015](https://freesound.org/s/531015/) · Noted451 | 1:10.885 | [MP3](https://cdn.freesound.org/previews/531/531015_9818404-hq.mp3) | water, ocean, waves, nature |
| `country-crickets` | 乡间夜虫 | [freesound:645863](https://freesound.org/s/645863/) · BonnyOrbit | 1:37.356 | [MP3](https://cdn.freesound.org/previews/645/645863_5902878-hq.mp3) | insects, crickets, night, nature, countryside |
| `quiet-night-city` | 静谧城市夜晚 | [freesound:427841](https://freesound.org/s/427841/) · leonelmail | 2:19.456 | [MP3](https://cdn.freesound.org/previews/427/427841_4437257-hq.mp3) | city, night, noise, focus |
| `city-rain` | 城市晚雨 | [freesound:607228](https://freesound.org/s/607228/) · RyanKingArt | 1:38.615 | [MP3](https://cdn.freesound.org/previews/607/607228_11069322-hq.mp3) | rain, city, night, traffic |

## 应用内分类

分类由上述标签生成，同一录音可进入多个分类。当前分类包括雨声、海浪与溪流、森林与鸟鸣、夜晚声景、壁炉、咖啡馆、阅读专注、列车旅途和城市空间。所有可见分类至少包含两条独立录音；分类只用于发现，不改变作品许可或来源。

## 视觉场景映射

声音视觉不是根据标题或图标猜测，而是由应用内审核目录的 `sceneStyle` 显式指定。它只影响低功耗 Canvas 画面，不影响音频 URL、许可或播放路由。

| 场景类型 | 对应录音示例 | 画面语义 |
|---|---|---|
| 窗边雨 / 城市晚雨 / 雷雨 | 窗边雨声、城市晚雨、远处雷雨 | 窗框雨痕、街灯倒影或远闪 |
| 海岸 / 溪流 / 水下 | 禅意海浪、林间溪流、水下空间 | 分层潮汐、石面涟漪、焦散与气泡 |
| 森林 / 微风 / 夜虫 | 林间树叶、冬日林鸟、旷野微风、夏夜虫鸣 | 树冠、叶影、月色与低频萤光 |
| 近景壁炉 / 暖炉房间 | 壁炉柴火、温暖炉火 | 原木、火焰、余烬与室内暖光 |
| 咖啡馆 / 图书馆 / 键盘 | 街角咖啡馆、安静图书馆、书桌键盘 | 杯口蒸汽、书架/书桌、键盘局部反馈 |
| 电车 / 列车 / 城市夜色 | 有轨电车车厢、列车行进、城市夜色 | 车窗视差、轨道灯带、城市灯光 |
| 抽象噪音 | 棕色噪音 | 克制模拟频谱；不复用于具象声音 |
