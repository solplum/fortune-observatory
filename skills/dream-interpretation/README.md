# lzl-dream · 纯传统中国占梦分析技能

面向 AI Agent（Claude Code / Codex / Antigravity / ZCode）的**纯传统占梦派**技能包：不混入现代西方心理学，专守先秦两汉占梦义理与明清占梦类书，通过确定性古籍检索脚本与四时五行气令推算，做到**条文可核验、多典可互证、现代意象明示取象类比、不恐吓不造神**。

---

## 核心特性

1. **辨源先于查辞**：依《周礼·占梦》六梦、《潜夫论·梦列》十梦及《黄帝内经·灵枢·淫邪发梦》先筛病梦、思梦与感梦，再辨直梦、象梦与反梦。
2. **先简明追问，答不出直接解**：默认先用 3–4 个轻巧问题补齐梦境转折结局、醒后体感、做梦时间与近期处境；若用户记不清或要求直接解，立刻按现有信息给出降级评估。
3. **3,505 条清洗古籍确定性检索**：内置零第三方依赖的 Python 检索与天文定气干支脚本 `scripts/dream_query.py`，支持繁简归一、108 组古今词桥接、22 组传统谐音取象提示及分书均衡召回。
4. **纯正合规语料来源**：全部语料均来自公开公版古籍（Public Domain）或 MIT 协议开源整理仓库，经清洗、分块、去噪、繁简统一与 SHA-256 校验后入库。

---

## 古籍知识库一览（总计 3,505 条）

| 典籍 / 语料文件 | 条目数 | 内容覆盖与说明 | 原始来源与协议 |
|---|---:|---|---|
| `references/corpus/menglin_xuanjie.jsonl` | 647 | 《梦林玄解》卷首序论、占繇三篇（观天地之会/辨二气之乘/审三辰之象）及 7 部 16 类梦占辞条 | `ycc77cn/skills` (MIT) & 中文维基文库 (Public Domain) |
| `references/corpus/duanmeng_mishu.jsonl` | 929 | 《断梦秘书》中编九类（子天文至申居处），完整保留（一）（二）（三）分注辨析 | `GaoRenYouShu/XuanJiPaiPan` (MIT) |
| `references/corpus/zhougong_27.jsonl` | 952 | 古本《周公解梦》二十七类 951 句互证定本 + 卷首总诗，附原刻异文校注 | `GaoRenYouShu/XuanJiPaiPan` (MIT) & `daizhigev20` (Public Domain) |
| `references/corpus/gujin_mengbu.jsonl` | 965 | 《钦定古今图书集成·历象汇编·庶徵典·梦部》（第 144–152 卷全数清洗分块：汇考、总论、艺文、六卷历代纪事、杂录、外编） | 中文维基文库 (Public Domain) |
| `references/corpus/classics_theory.jsonl` | 12 | 《周礼·占梦》《潜夫论·梦列》《列子·周穆王》《灵枢·淫邪发梦》《论衡·订鬼》《阿难七梦经》及道藏《黄帝龙首经》《解恶梦品》《法海遗珠》 | `daizhigev20` & `kanripo` (Public Domain) |

> 收录边界说明：《梦林玄解》当前收录卷首理论与 7 部 16 类梦占辞条；《断梦秘书》酉饮食、戌器物、亥珍宝三类公开文本暂缺；如实登记，绝不补编。

---

## 目录结构

```text
lzl-dream/
├── SKILL.md                          # 技能主提示词与四段式解梦工作流
├── README.md
├── references/
│   ├── classical-methodology.md      # 六梦/十梦辨源、《梦林玄解》占繇与梦变心法
│   ├── shiling-wuxing.md             # 四时五行旺相休囚死与昼夜时段权重
│   ├── wuzang-bingmeng.md            # 《灵枢·淫邪发梦》五脏病梦筛查表
│   ├── mengrang-rules.md             # 传统梦禳观念与现代省身避坑转化
│   ├── synonym-xieyin.json           # 繁简归一表(3,240字)、古今桥接(108组)、谐音(22组)
│   └── corpus/                       # 5 份清洗后 JSONL 语料 + manifest.json
└── scripts/
    ├── build_corpus.py               # 语料抓取、清洗、繁简归一与 SHA-256 打包脚本
    ├── dream_query.py                # 确定性检索、浏览器浏览、库校验与干支时令引擎
    └── test_dream_query.py           # 完整性、检索精度与历法一致性单元测试
```

---

## 本地校验与 CLI 用法

本技能脚本仅使用 Python 3 标准库，**无需额外 `pip install`**：

```bash
# 1. 校验语料库完整性与统计
python3 scripts/dream_query.py stats

# 2. 检索梦象原文并推算当日干支与四时旺衰
python3 scripts/dream_query.py search --q "黑蛇 咬 打死" --date 2026-11-24 --period 平旦 --limit 15

# 3. 现代意象取象桥接检索
python3 scripts/dream_query.py search --q "房子 倒塌" --with-time --limit 12

# 4. 查阅五脏病梦或梦禳理论原文
python3 scripts/dream_query.py search --q "淫邪发梦" --layer theory --limit 5
python3 scripts/dream_query.py search --q "解恶梦" --layer rang --limit 5

# 5. 运行全套单元测试
python3 scripts/test_dream_query.py -v
```

---

## 协议

本项目遵循仓库根目录的 **MIT License**；清洗后的公版典籍（Public Domain）与开源参照数据（MIT / OpenCC Apache-2.0）均已在 `references/corpus/manifest.json` 注明上游出处与许可。
