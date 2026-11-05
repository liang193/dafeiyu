# 统一面板、记忆与 QQ 控制适配

本分支基于上游大肥鱼，增加以下本机部署功能：

- Windows `Start.cmd` 统一启动现有 Ubuntu WSL、NapCat 与 Linux 控制台，并打开当前有效地址；重复启动复用后台进程。
- 主面板内嵌 QQ 登录、B站和小红书控制页；NapCat 和 OneBot 凭证在授权后的本机请求中自动读取。
- 可选的本机模型 Key 保存，目录 700、文件 600，与项目源码、聊天状态分开；Key 与模型 Base URL 绑定。
- 基于 dsh-ai-memory 0.2.0 的原始 MIT 账本核心：共享已确认人格和公开阅读见闻，QQ 按账号、会话和说话人分别存储。人格候选需在本机面板确认。
- 在「QQ 文字控制」指定控制号后，可从 QQ 启动、暂停、查询 B站和小红书任务；支持固定自然语言口令和模型工具。控制人授权与聊天名单分开。
- 浏览默认自动参与并允许评论；明确要求「只看不评论」时进入只读模式。沿用已有数量、时长、间隔与发送额度。
- QQ 空间纯文字草稿与发布适配。实际发布由部署选项启用；缺少登录态、账号不符或发布结果不明时不重试。

## 本机运行布局

`runtime/` 是适用于既有 Ubuntu WSL 部署的启动器和 systemd 模板，预期布局如下：

```text
/opt/feiyu/source/                         Linux 源码与 dist/dafeiyu-linux
/opt/feiyu/bin/manage-feiyu.py              runtime/manage-feiyu.py
/opt/feiyu/runtime/memory-bridge.mjs        runtime/memory-bridge.mjs
/opt/feiyu/integrations/dsh-ai-memory-main/ integrations 中的 MIT 核心
/var/lib/feiyu/                            feiyu 服务用户的私有数据目录
```

Linux 编译和浏览器依赖按 [WINDOWS.md](WINDOWS.md) 安装。实际服务使用 `runtime/feiyu-engine.service`，QQ 容器初始化见 `runtime/setup-bridge.sh`。服务用户为 `feiyu`；systemd 服务、数据权限和启动器路径需与上述布局一致。不要把运行数据复制进仓库。

部署参数放在 `/var/lib/feiyu/private/deployment.env`，不要修改或提交自己的凭证和账号。示例：

```ini
DAFEIYU_MODEL_BASE_URL=https://your-compatible-provider.example/v1
DAFEIYU_QZONE_PUBLISH=0
```

需要自主发 QQ 空间文字动态时，明确将 `DAFEIYU_QZONE_PUBLISH` 改为 `1` 后重启服务。模型名称在本机面板配置；模型 Key 首次在本机连接页填写。B站、小红书首次登录、核对和绑定可从 QQ 发起，扫码仍由使用者完成。

## QQ 口令示例

- `去刷一下 B站`
- `去小红书看看猫咪，十分钟后停`
- `去刷 B站，只看不评论`
- `暂停小红书` / `B站进度` / `停一下`
- `登录B站` → `核对B站账号` → `确认绑定B站账号`

QQ 需已连接并处于回复运行状态，群内使用真正的 @。任务与面板操作复用同一 SocialEngine。普通好友和网页内容无法改变控制人设置。

## 验证状态

已通过 Linux Swift 测试、合成 OneBot 事件与浏览器面板检查，包括：跨平台公开记忆召回、会话/群成员隔离、人格确认、控制号持久化、未授权拒绝、重复事件去重、只读/自动模式、纯文字发布的单次提交和未知结果不重发。

`python3 runtime/test-memory-bridge.py` 使用临时合成数据验证记忆适配。其他检查沿用 `scripts/test.sh`、`scripts/build-linux.sh`、`scripts/test-control-panel.py <Linux executable>` 和 `scripts/check-public.py`。

没有主动向真实 QQ 联系人发送测试消息、真实评论或测试动态。QQ 空间外部接口尚需真实账号验收，不能将合成测试等同于线上发布成功。美团、淘宝尚未在此基础分支中接入。
