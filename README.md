# instabox-keepalive

用 GitHub Actions 让免费的 [instabox](https://instabox.sh) 沙箱近似常驻。

免费机器有两个会让它停下来的限制：

1. **闲置 30 分钟自动暂停**（固定，免费版关不掉）。
2. **连续运行 480 分钟（8 小时）强制暂停**，随后 10 分钟冷却期内无法唤醒。

本仓库的定时任务每 10 分钟跑一次 `keepalive.sh`：

- 机器若已暂停/停止，先唤醒；
- 执行一条空命令登记活动，重置 30 分钟闲置计时；
- 运行时长接近 8 小时上限时，**提前** `suspend` + `resume`，赶在强制暂停前把计时器清零，从而永远不触发冷却。`suspend`/`resume` 会保留进程和内存。

> 实测：suspend/resume 后进程完整保留，`runStartedAt` 会重置。

## 启用

1. 生成一个 **只含 `machines:write` 权限** 的 API key：
   `instabox keys create --name keepalive --scope machines:write`
2. 在仓库 **Settings → Secrets and variables → Actions** 添加：
   - Secret `INSTABOX_API_KEY` = 上面的 key
   - （可选）Variable `INSTABOX_BOX` = 你的机器名，默认 `box-eecd4f`
3. 到 **Actions** 页启用 workflow，点 `Run workflow` 手动跑一次验证。

## 注意

- GitHub 定时任务在仓库 60 天无提交后会自动停用，偶尔推一次或手动触发即可。
- 轮换时服务会有几秒停顿。
- 保活可能不符合服务条款，自行评估；别在免费机器上放重要数据。
