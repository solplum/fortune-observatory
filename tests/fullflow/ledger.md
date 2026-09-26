# destiny 挂账台账（fullflow）

- 用途：run-all SKILL.md 工作流第 7 步「启动对账」载体；run-all 开跑前必须先对账本台账与黑名单。
- 建档：2026-09-26（建档时完成首轮对账，记录见下）。

## 1. 口头挂账关键词扫描（2026-09-26）

- 命令：`grep -rn -E "待真网|待联测|待真机|待人耳|待复测|待验收" .`（项目根，排除 .git/node_modules/.venv）
- 结果：**0 命中**。5 个权限受限目录未扫（`.Codex/cache/pytest-arbiter-*` ×4、`tests/.tmp`），均为工具运行缓存，非项目文档/README/交付摘要。
- 前置扫描（带 `--include="*.md" --include="*.yaml" --include="*.yml" --include="*.json"` 的全项目 grep）同样 0 命中。
- 结论：无六关键词口头挂账可补录；以下 L1/L2 为从轮次报告与源码证据补录的开口项（宁多录不漏录）。

## 2. 台账

| # | 事项 | 卡点 | 收口判据 | 来源 | 状态 |
|---|------|------|---------|------|------|
| L1 | deploy.sh 不清理线上旧 bundle，累计 17 个历史 bundle ≈10MB | dist 清理未实现、未排期（报告仅标注「建议下轮加 dist 清理」） | deploy.sh 增加 dist 旧资产清理且部署后线上无冗余 bundle；或明确拍板不清理 | reports/2026-09-23-runall-门0门2汇总.md 第 68 行（运维注）＋ scripts/deploy/deploy.sh:37（`sudo cp -r "$STAGE"/. "$APP_DIR"/` 无清理，2026-09-26 实测在位） | 仍挂 |
| L2 | 跨境无 CDN 首屏 40s+（产品侧议题） | 无 CDN/加速方案，产品侧未拍板；09-23 轮 F2「已解」口径（梯子带宽 425KB/s）可能已实质缓解，但无显式收口记录 | 产品拍板（加 CDN 或接受现状）；或有首屏实测达标记录 | reports/2026-09-04-summary.md 第 30 行；09-23 汇总报告第 54 行（F2 已解） | 仍挂（疑似已实质缓解，待拍板） |
| L3 | 非流式 /v1/dreams/interpret 的 essay 以裸 `<think>` 开头无闭合、英文思考混中文正文、结尾半截截断（E-R3，2026-09-26 门2 实测复现，响应体 c3_dream_plain_resp.json）；流式管线正常 | 后端未修；manifest.yaml 门1 清单对 essay 缺 json.not_contains 断言（回归基线 R3 在非流式端点的落点） | 后端剥离/闭合 think 后，manifest.yaml dream_interpret 补 `json.not_contains: <think>` 断言并复跑门1+门2 审计 E-R3 转 PASS | run-all 首战 2026-09-26 门2 审计 E-R3 | 仍挂 |
| L4 | index.html:8 CSP 缺 font-src，内嵌 woff2 阅读字体被拦 30 次降级本地楷体；favicon 404 1 次 | 前端未修 | CSP 补 font-src（或字体改同源自托管）后控制台零字体拦截；favicon 补文件 | run-all 首战 2026-09-26 门2 审计顺带发现 | 仍挂 |
| L5 | 双用户切换运行时确认未完成：E-R11 UI 驱动被浏览器工具 30s 硬限反复截断 | 工具时限；补偿证据已有（DomainAnalysisConsole.tsx:183 key={aiOwner} 重挂在位 + 存储按 owner UUID 分槽），缺运行时切换实证 | 下轮门2 分步驱动完成双用户切换实测，断言无跨用户数据串槽 | run-all 首战 2026-09-26 门2 审计 E-R11 | 仍挂 |
| L6 | 门0 warning×4 待拍板（unconfirmed，无 blocking）：①解梦 is_referral 裸子串匹配可被「自␣残」/零宽字符绕过（tcm 已有 _normalize_signal_text 加固，解梦未复用——人身安全路由）；②Dockerfile 缺 COPY skills/ 且 .dockerignore `*.md` 剥语料，Docker 镜像 AI 静默退化（deploy.sh tarball 生产路径不受影响）；③scripts/verify_release.py 永远红失修；④check-life-phase.ts import 不存在的 lifePhase 模块（死脚本） | 用户未拍板修复优先级 | 拍板后逐项修；①最窄修法=is_referral 复用 tcm 归一化 + test_safety_alignment.py 补绕写法回归测试 | run-all 首战 2026-09-26 门0 | 待拍板 |

## 3. 历史挂账状态核对（2026-09-26）

- 09-23 第三轮「挂账清单（铁律 9）」：三轮后全部收口，无剩余挂账（reports/2026-09-23-runall-门0门2汇总.md 第 70–72 行）。W5/W3/W4/S5/W7/S6/S7 于 commit 77b409b 落地；F1 同 commit 用户拍板移除；F2 已解。
- 09-04 轮运维挂账：apiBase.ts:2 PROD fallback 改 "/api" 已由 commit dda86c6 落地（2026-09-05）；其余遗留即 L2。

## 4. 与回归基线黑名单联动（2026-09-26 对账）

- 本轮对账向 `C:\Users\20212\.agents\skills\run-all\references\regression-baselines.md` 登记格式表新增 **R8–R15 共 8 条**（来源：09-23 门0 修复 B1/B2、第二轮治理 W1/W2/S3/S4/W6、思考期进度条改造 f08263a）。
- 待定未登记 7 项（W5/F1 红线移除、W3 断线续传、W4 流帽顺序、S6/W7 值口径、S7 复闪、安全审计三轮）见当轮对账 summary，登记完成前相关缺陷按铁律 10 不算收口。
