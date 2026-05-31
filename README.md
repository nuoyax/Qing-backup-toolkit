# Qing Backup Toolkit

备份与恢复 Windows 上的**敏感配置**、**源代码**、**文档**与**大文件**，全部支持多核并行；**默认压缩**为与文件夹同名的 zip（可关闭），按类型分目录存放。

## 入口（推荐从主菜单进入）

双击 **`Qing-backup.bat`** 打开主菜单：

| 选项 | 脚本 | 说明 |
|------|------|------|
| 1 | `test_backup.bat` | 快速测试（约 5 秒） |
| 2 | `backup.bat` | 敏感配置备份（分类多选） |
| 3 | `backup_code.bat` | 全盘源代码（优先 .git 工程，其次 README 工程） |
| 4 | `backup_docs.bat` | 全盘文档（500MB 以下） |
| 5 | `backup_large.bat` | 磁盘大文件（默认 ≥500MB） |
| 6 | `restore.bat` | 恢复 / 导出下载 |
| 7 | README | 查看完整文档 |

## 目录结构

```
Qing-backup-toolkit/
  Qing-backup.bat       # 主入口（菜单）
  backup.bat            # 敏感配置
  backup_code.bat       # 源代码
  backup_docs.bat       # 文档
  backup_large.bat      # 大文件
  restore.bat           # 恢复/导出
  test_backup.bat       # 快速测试
  lib/
    catalog.ps1         # 分类定义
    common.ps1          # 压缩、并行复制/恢复
    scan_worker.ps1     # 并行磁盘扫描
    backup.ps1
    restore.ps1
  test_output/
```

## 输出目录命名（按类型区分）

```
Administrator_2026-05-31_143052_config_backup/   # 敏感配置
Administrator_2026-05-31_143052_code_backup/     # 源代码
Administrator_2026-05-31_143052_docs_backup/     # 文档
Administrator_2026-05-31_143052_large_backup/    # 大文件
```

每个备份包内容：

```
*_backup/
  Administrator_2026-05-31_143052_config_backup/   # 清单与报告
  Administrator_2026-05-31_143052_config_backup.zip  # 可选：与文件夹同名，同级存放
  manifest.json
  backup_report.md
  backup.log
```

## 功能说明

### 1. 敏感配置备份（选项 2）

- 单文件默认上限 **100 MB**，源盘默认 C，可按分类多选
- 仅含 **SSH/IDE/浏览器/聊天/代理** 等配置项，以及桌面/个人/密钥扫描
- **不含** 全盘源代码、文档、大文件（请用菜单 3/4/5）
- 并行线程数默认 **CPU 核心数**

### 2. 全盘源代码备份（选项 3）

- 优先扫描含 **`.git`** 的工程目录，其次扫描含 **`README`** 的目录
- **自动排除依赖目录**：`node_modules`、`venv`、`.rustup`、`.cargo`、`vendor`、`target` 等
- 输出到 `*_code_backup/`

### 3. 全盘文档备份（选项 4）

- 扫描 Word/Excel/PPT/PDF/TXT 等文档
- 单文件 **500 MB 以下**
- 输出到 `*_docs_backup/`

### 4. 磁盘大文件备份（选项 5）

- 默认 **500 MB 以上**（可自定义阈值与单文件上限）
- 输出到 `*_large_backup/`

### 5. 恢复 / 导出（选项 6）

1. 选择备份包
2. **自动识别**备份中包含的工具/分类（SSH、Cursor、源代码等）
3. 选择要恢复的分类
4. 两种模式：
   - **恢复到原路径**（原文件备份为 `.bak.时间戳`）
   - **导出到指定目录**（下载式恢复，保留分类目录结构）
5. 并行恢复，默认 CPU 核心数

```bat
restore.bat "D:\backups\Administrator_2026-05-31_143052_config_backup"
```

## 快速测试

双击 **`test_backup.bat`**：仅备份 SSH/Git、Cursor、开发工具链 3 类，输出到 `test_output/`。

## 注意事项

1. 备份含私钥/令牌，请妥善保管
2. 源代码/文档/大文件全盘扫描可能耗时较长，请耐心等待进度条
3. 单个文件/目录出错会自动跳过并记录到 `backup.log`，不影响其余备份
4. 旧版未压缩备份（含 `files/` 目录）仍可正常恢复

## 自定义

- 增删备份项：`lib/catalog.ps1`
- 代码依赖排除：`Get-CodeDependencyExcludePatterns`
- 扫描排除规则：`lib/scan_worker.ps1` → `Get-DefaultExcludePatterns`
