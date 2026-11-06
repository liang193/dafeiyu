# 淘宝 / 美团购物实验

双击项目根目录的 `Commerce.cmd` 打开购物面板和现有 Ubuntu WSL 里的 `FeiYuCommerce` 安卓虚拟手机。这个实验单独运行，不需要修改 QQ 登录、控制名单或重复输入模型 Key；复用大肥鱼本机保存的 Key 和模型。它还没有接入 QQ 的文字命令。

1. 选择 App，点「打开 App 并手动操作」，直接点右侧手机画面。用 App 的键盘自己处理首次协议、登录、验证码和定位选择。需要时请在 App 内选好配送地址。手动操作时 AI 不会同时控制手机。
2. 在面板输入任务。例如「淘宝搜索 500ml 保温杯，比较两款商品」；验证到确认页时请明确商品、规格、数量，以及「付款前停止」。
3. 点「开始 AI 任务」。右侧显示虚拟手机的最近画面；在识别到订单确认、提交订单或支付入口时停止。若页面无法读取、要登录或验证，点「手动操作当前画面」接管。面板提供「停止」，停止后不会再执行已返回的模型动作。

手动登录和滑动页面时，可以双击 `Commerce-Live.cmd`，在 Windows 的 **FeiYu Android Live** 窗口操作同一台虚拟手机。首次运行会下载并校验 [scrcpy 官方 Windows 发行包](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1)。该窗口使用 H.264 连续投屏，帧率上限 30 FPS。运行 AI 任务时，请把虚拟手机留给 AI 操作。

实验限制：模型读取可访问性节点，不能任意点坐标、运行 shell、打开其他 App、输入登录信息或支付。搜索、商品详情、规格、购物车和到确认页的路径仍需在真实登录后逐个平台验收。界面变化可能让实验提前暂停。付款和最终提交由使用者完成。实验不启动定时任务，不向真实 QQ 联系人发送消息。

## 本机已验证

| 路线 | 实际结果 |
| --- | --- |
| 淘宝网页 | 首页 HTTP 可达；内置浏览器读取超时，搜索响应未验证出可操作的商品列表。网页结算未验收。 |
| 美团网页 | [美团官网](https://www.meituan.com/)及[美团外卖网页](https://waimai.meituan.com/)可达。网页结算未验收。 |
| WSL 安卓模拟器 | Ubuntu 内 KVM 加速可用，Android 11 Google APIs x86_64 镜像启动完成，支持 ARM 应用。 |
| 美团 App | 官方站点下载的 `com.sankuai.meituan` 12.68.402 安装成功，运行到首次协议页面，读取到无障碍节点并截图。 |
| 淘宝 App | 官方 CDN 的 `com.taobao.taobao` 10.68.10 安装成功，运行到首次协议页面，读取到无障碍节点并截图。 |
| 模型与拦截 | 现有模型成功为合成页面生成了可校验的动作；夹具覆盖搜索→详情→规格→购物车→确认页及付款拦截。本次真实 App 尚待登录后验收，未创建订单、未付款。 |

## 安装与复现

以已安装大肥鱼的 Ubuntu WSL x86_64 和 `feiyu` 服务用户为基础，需要 WSLg、可用的 KVM、Python 3.11+（本机为 3.14）和约 8 GB 可用 Linux 磁盘。安装依赖 `libpulse0 libxkbcommon-x11-0 libxcb-cursor0`。官方工具和系统镜像见 [Android Emulator](https://developer.android.com/studio/run/emulator-commandline)。APK、系统镜像和下载完整性信息见 `software.json`；下载到本机忽略的 `runtime/downloads`。应用下载链接可能返回更新版本，哈希变化时请核对来源并明确更新记录。

从此目录在 WSL 中运行（将 `DOWNLOADS` 改为下载目录）：

```bash
sudo python3 install-sdk.py "$DOWNLOADS"
sudo python3 -m venv /opt/feiyu/commerce-venv
sudo /opt/feiyu/commerce-venv/bin/python -m pip install -r requirements.txt
sudo install -d /opt/feiyu/commerce
sudo install -m 644 commerce.py panel.html software.json /opt/feiyu/commerce/
sudo install -m 644 feiyu-commerce*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start feiyu-commerce.service
sudo -u feiyu -H python3 install-apps.py "$DOWNLOADS"
python3 test_commerce.py
```

首次 Android 启动结束后再安装 App。如果 WSL 不能直连软件源，可在 Windows 下载已校验的归档和 Python wheel，再离线安装。安卓自动化基于 [uiautomator2](https://github.com/openatx/uiautomator2)。

模型依赖本机 `model-key.json`（保存地址与 Key 对应）和 QQ 模型设置。`DAFEIYU_COMMERCE_MODEL` 可通过 systemd 环境覆盖模型名称。实验面板、ADB 和模拟器控制端口只监听回环。虚拟手机的应用数据和面板截图在 `/var/lib/feiyu/` 的私有目录，关闭后保留，勿提交到仓库。仅浏览/搜索页面中的必要文本发送给已配置的模型接口；被识别为登录、验证和结算的页面在请求模型之前停止。

如果关闭窗口，双击 `Commerce.cmd` 可以继续。仅停止实验服务可运行 `sudo systemctl stop feiyu-commerce.service feiyu-commerce-phone.service`。
