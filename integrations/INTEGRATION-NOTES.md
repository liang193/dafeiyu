# 上游来源与本机适配

- dsh-ai-memory：https://github.com/Isyyyue/dsh-ai-memory ，package version 0.2.0，MIT；保留原 src 和 LICENSE，runtime/memory-bridge.mjs 通过公开导出 openLibrary/createOperations 复用核心。未注册到用户现有 DSH profile，也未读取其会话或记忆。
- QQ 空间协议参考：https://github.com/diaomin66/astrbot_plugin_qzone_ultra 的 qzone_bridge/client.py 中 publish_mood；本机 Swift 适配使用固定 QQ 空间端点、纯文字参数和 NapCat 凭证，不启动 AstrBot。保留上游下载源码及其许可证供查阅。
- NapCat 凭证接口：https://napneko.github.io/onebot/api 的 get_credentials/get_login_info/get_status。

上游下载归档仅用于本机集成，不应把私有数据、Cookie、真实账号配置或 API Key 放进这些目录。

dsh-ai-memory-main.zip 的 SHA-256：1FF3CF8C5994CC925DBA5B31885DCB00F2D3FD0D022595D26ADC2C63BF257B40。部署使用此下载快照，更新上游时应重新核对并测试。
