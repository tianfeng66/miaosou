<p align="center">
  <img src="Assets/icon-source.jpg" width="128" height="128" alt="秒搜">
</p>

<h1 align="center">秒搜</h1>

<p align="center">
  macOS 上的文件名秒搜，用法对齐 Windows 的 <a href="https://www.voidtools.com/">Everything</a>。<br>
  打开窗口，输入几个字，立刻看到文件名和路径。
</p>

<p align="center">
  <a href="#安装">安装</a> ·
  <a href="#用法">用法</a> ·
  <a href="#从源码编译">从源码编译</a> ·
  <a href="#命令行">命令行</a>
</p>

---

## 这是什么

Windows 上 Everything 之所以快，是因为它直接读 NTFS 的主文件表。macOS 对应的现成索引是 **Spotlight**。秒搜不再扫一遍全盘，而是查本机已经建好的 Spotlight 索引，所以第一次打开就能搜。

- 输入即搜，支持 `*` `?` 通配符、空格表示同时包含
- 按类型筛选：全部 / 文件 / 文件夹 / 图片 / 视频 / 文档
- 范围可选「主目录」或「整台电脑」
- 回车打开，⌘↩ 在访达中显示，⌘⇧C 拷贝完整路径
- 只在本机查文件名，不上传任何内容

系统要求：macOS 14 或更高。安装包是通用二进制，Apple 芯片和 Intel 都能用。

## 安装

到 [Releases](../../releases/latest) 下载，三选一：

| 文件 | 怎么用 |
|---|---|
| **秒搜-1.0.0.pkg** | 双击，按提示装进「应用程序」（推荐） |
| **秒搜-1.0.0.dmg** | 打开后把秒搜拖到「应用程序」 |
| **秒搜-1.0.0.zip** | 解压后得到 `秒搜.app` |

第一次打开如果提示「无法验证开发者」：按住 **Control** 再点图标，选择「打开」。这是未使用 Apple 开发者账号公证时的正常情况。

需要搜「下载」等受保护目录时：系统设置 → 隐私与安全性 → **完全磁盘访问权限** → 打开「秒搜」。

## 用法

| 操作 | 说明 |
|---|---|
| 直接输入 | 按文件名即时过滤 |
| `截图 发票` | 空格表示文件名里同时包含这些词 |
| `*.png` / `报告?.docx` | 通配符 |
| `ext:pdf` | 按后缀 |
| `发票 /Downloads` | 文件名含「发票」，且路径里有 Downloads |
| `folder:` / `file:` | 只看文件夹 / 只要文件 |
| Enter / 双击 | 打开 |
| ⌘Enter 或 ⌘R | 在访达中显示 |
| ⌘⇧C | 拷贝完整路径 |
| Esc | 清空搜索框 |
| ↓ | 从搜索框跳到结果列表 |

顶部可以切换类型和搜索范围。默认隐藏 `/System`、`/Library` 等系统路径。

### 搜不到某些文件时

1. 把范围改成「整台电脑」
2. 取消勾选「隐藏系统文件」
3. 给秒搜打开「完全磁盘访问权限」
4. 确认 Spotlight 没有排除那个文件夹：系统设置 → Spotlight → 搜索隐私

## 从源码编译

需要 Xcode Command Line Tools。

```bash
git clone https://github.com/tianfeng66/miaosou.git
cd miaosou
./build.sh
open 秒搜.app
```

打安装包（pkg / dmg / zip）：

```bash
./package.sh
# 产物在 dist/
```

## 命令行

编译完成后可以用同一套搜索：

```bash
./miaosou README
./miaosou "*.png"
./miaosou 发票 --json
```

也可以直接：

```bash
秒搜.app/Contents/MacOS/Miaosou --search README
```

## 说明

本工具只在本机查询 Spotlight 索引，不访问网络、不上传文件。文件增减一般会由 macOS 自动更新索引。

## License

MIT
