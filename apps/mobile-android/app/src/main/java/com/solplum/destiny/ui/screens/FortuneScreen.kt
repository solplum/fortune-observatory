package com.solplum.destiny.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.solplum.destiny.data.Repo
import com.solplum.destiny.model.DailyTransitResponse
import com.solplum.destiny.model.GanZhi
import com.solplum.destiny.model.TransitResponse
import com.solplum.destiny.model.WindowTransitResponse
import com.solplum.destiny.net.ApiResult
import com.solplum.destiny.net.StreamBus
import com.solplum.destiny.state.Memory
import com.solplum.destiny.ui.DestinyColors
import com.solplum.destiny.ui.ErrorBar
import com.solplum.destiny.ui.GateCard
import com.solplum.destiny.ui.LoadingRow
import com.solplum.destiny.ui.SectionTitle
import com.solplum.destiny.ui.StreamPanel
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

private val PERIODS = listOf("今日", "明日", "本周", "本月")

@Composable
fun FortuneScreen(nav: NavController) {
    val birth = Memory.birth
    if (birth == null) {
        Column(Modifier.fillMaxSize().padding(16.dp)) {
            GateCard(
                title = "运势需要先完成一次排盘",
                hint = "运势按你的出生资料计算流日与流年，先去排盘生成命盘。",
                buttonText = "去排盘",
                onButton = { nav.navigate("chart") },
            )
        }
        return
    }

    var period by remember { mutableStateOf("今日") }
    var loading by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    var daily by remember { mutableStateOf<DailyTransitResponse?>(null) }
    var window by remember { mutableStateOf<WindowTransitResponse?>(null) }
    var layers by remember { mutableStateOf<TransitResponse?>(null) }

    suspend fun fetch(p: String) {
        loading = true
        err = null
        val today = LocalDate.now(ZoneId.of("Asia/Shanghai"))
        val r = when (p) {
            "今日" -> Repo.dailyTransit(birth, today.toString())
            "明日" -> Repo.dailyTransit(birth, today.plusDays(1).toString())
            "本周" -> {
                val mon = today.with(DayOfWeek.MONDAY)
                Repo.transitWindow(birth, mon.toString(), mon.plusDays(6).toString())
            }
            else -> {
                val first = today.withDayOfMonth(1)
                Repo.transitWindow(birth, first.toString(), first.withDayOfMonth(first.lengthOfMonth()).toString())
            }
        }
        when (r) {
            is ApiResult.Ok -> {
                err = null
                when (val data = r.data) {
                    is DailyTransitResponse -> {
                        daily = data
                        window = null
                        Memory.lastZiweiContext = data.ai_context
                        Memory.lastBaziContext = data.ai_context_bazi
                    }
                    is WindowTransitResponse -> {
                        window = data
                        daily = null
                        Memory.lastZiweiContext = data.ai_context
                        Memory.lastBaziContext = data.ai_context_bazi
                    }
                }
            }
            is ApiResult.Err -> err = r.message
        }
        // 时间层事实（契约 §3.4 端点 #6）：与 Web 一致仅在单日视图并行拉取、失败可降级（App.tsx:576-596 口径）
        if (p == "今日") {
            layers = when (val t = Repo.transits(birth, today.toString())) {
                is ApiResult.Ok -> t.data
                is ApiResult.Err -> null
            }
        } else {
            layers = null
        }
        loading = false
    }

    LaunchedEffect(period) { fetch(period) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PERIODS.forEach { p ->
                FilterChip(
                    selected = period == p,
                    onClick = { period = p },
                    label = { Text(p, Modifier.heightIn(min = 24.dp)) },
                    colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
                )
            }
        }
        if (loading) LoadingRow("正在计算 $period 运势…")
        err?.let { ErrorBar(it) }

        daily?.let { DailyCard(it) }
        layers?.let { TimeLayersCard(it) }
        window?.let { WindowCard(it) }

        AiReadingSection("我的${period}运势")
        StreamPanel(StreamBus.state.collectAsState().value)
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun FactRow(relation: String, natal: String, transit: String) {
    val (bg, label) = when (relation) {
        "branch_clash" -> DestinyColors.Accent2.copy(alpha = 0.12f) to "冲"
        "branch_combination" -> DestinyColors.GoodBg to "合"
        "branch_same" -> DestinyColors.Wash to "同"
        else -> DestinyColors.SoftLine to "·"
    }
    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(
            label,
            Modifier
                .background(bg, RoundedCornerShape(4.dp))
                .border(1.dp, DestinyColors.SoftLine, RoundedCornerShape(4.dp))
                .padding(horizontal = 6.dp, vertical = 1.dp),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.width(8.dp))
        Text("行运 $transit 遇 本命 $natal", fontSize = 13.sp, fontFamily = com.solplum.destiny.ui.ReadingFont)
    }
}

@Composable
private fun DailyCard(data: DailyTransitResponse) {
    val t = data.transit
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text(
                    "${t.transit_date} · 日柱 ${t.day_pillar}",
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                )
                Spacer(Modifier.weight(1f))
                val keyword = when {
                    t.facts.any { it.relation == "branch_clash" } -> "变动日"
                    t.facts.any { it.relation == "branch_combination" } -> "顺合日"
                    t.facts.isNotEmpty() -> "平稳日"
                    else -> "平常日"
                }
                Text(
                    keyword,
                    Modifier.background(DestinyColors.Wash, RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 2.dp),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
            if (t.facts.isEmpty()) {
                Text("本日与本命四柱无冲合关系，平稳平常。", fontSize = 13.sp, color = DestinyColors.Muted)
            } else {
                t.facts.forEach { f -> FactRow(f.relation, f.natal_pillar, f.transit_pillar) }
            }
            data.ziwei_yearly?.let { zy ->
                SectionTitle("紫微流年")
                Text(
                    "流年 ${zy.year_pillar} · 虚岁 ${zy.nominal_age} · 流年命宫在 ${zy.life_branch}",
                    fontSize = 12.5.sp,
                    color = DestinyColors.Muted,
                )
                zy.yearly_mutagens.forEach { m ->
                    Text("${m.star}${m.mutagen} → ${m.palace_name}（${m.palace_branch}）", fontSize = 12.5.sp)
                }
                zy.flowing_stars.forEach { s ->
                    Text("流曜 ${s.star} → ${s.branch}", fontSize = 12.sp, color = DestinyColors.Muted)
                }
            }
        }
    }
}

private fun periodCn(p: String): String = when (p) {
    "great_luck" -> "大运"; "year" -> "流年"; "month" -> "流月"; "day" -> "流日"
    else -> p
}

private fun signalCn(d: String): String = when (d) {
    "support" -> "助力"; "tension" -> "紧张"; "neutral" -> "中性"
    else -> d
}

@Composable
private fun TimeLayersCard(data: TransitResponse) {
    val t = data.transit
    var expanded by remember { mutableStateOf(false) }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                Modifier.fillMaxWidth().clickable { expanded = !expanded }.heightIn(min = 32.dp),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
            ) {
                Text("时间层事实（大运/流年/流月/流日）", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                Text(if (expanded) "▾" else "▸", color = DestinyColors.Muted)
            }
            if (expanded) {
                val layerLine = t.layers
                    .filter { it.pillar.isNotBlank() }
                    .joinToString(" · ") { "${periodCn(it.period)} ${it.pillar}" }
                if (layerLine.isNotEmpty()) {
                    Text(layerLine, fontSize = 13.sp, fontFamily = com.solplum.destiny.ui.ReadingFont)
                }
                t.ziwei_annual?.palaces?.takeIf { it.isNotEmpty() }?.let { palaces ->
                    Text(
                        "流年宫位：" + palaces.joinToString("、") { "${it.name}（${it.branch}）" },
                        fontSize = 12.sp,
                        color = DestinyColors.Muted,
                    )
                }
                t.signals.forEach { s ->
                    Text("规则信号：${signalCn(s.direction)}", fontSize = 12.5.sp)
                }
                t.insights.forEachIndexed { i, ins ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .background(DestinyColors.Wash.copy(alpha = 0.25f), RoundedCornerShape(8.dp))
                            .padding(8.dp),
                    ) {
                        Text("${i + 1}. ${ins.title}", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        Text(ins.summary, fontSize = 12.sp, lineHeight = 18.sp)
                        if (ins.action.isNotBlank()) {
                            Text("可以先做：${ins.action}", fontSize = 11.5.sp, color = DestinyColors.Accent)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WindowCard(data: WindowTransitResponse) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                "${data.transit.start_date} ~ ${data.transit.end_date}",
                fontWeight = FontWeight.Bold,
                fontSize = 15.sp,
            )
            data.transit.daily.forEach { d ->
                val rel = d.facts.joinToString("、") { GanZhi.relationText(it.relation) }
                Text(
                    buildString {
                        // transit_date 契约形状 YYYY-MM-DD：取 MM-dd 展示（原 String.format 误用是死代码）
                        append(d.transit_date.takeLast(5))
                        append("  ")
                        append(d.day_pillar)
                        if (rel.isNotEmpty()) append(" · $rel")
                    },
                    fontSize = 13.sp,
                    fontFamily = com.solplum.destiny.ui.ReadingFont,
                    color = if (rel.contains("冲")) DestinyColors.Accent2 else DestinyColors.Ink,
                )
            }
        }
    }
}

@Composable
private fun AiReadingSection(periodLabel: String) {
    val zwToken = Memory.lastZiweiContext?.token.orEmpty()
    val bzToken = Memory.lastBaziContext?.token.orEmpty()
    var started by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle("AI 解读")
        if (zwToken.isEmpty() && bzToken.isEmpty()) {
            Text(
                "本次运势响应未携带解读上下文（服务端未配置或盘面未核验），无法发起 AI 解读。",
                fontSize = 12.5.sp,
                color = DestinyColors.Muted,
            )
        } else {
            Button(
                onClick = {
                    started = true
                    // 契约 §4.2：运势场景为单 token（服务端 _verified_context 只允许
                    // {fortune.daily,fortune.period} 组合或 domain+单体系盘——fortune.daily 与
                    // ai_context_bazi 的 bazi.chart 混搭必 400，ai_explainer.py:318-338 实证）。
                    // 优先紫微口径（ai_context），缺失时退八字口径（ai_context_bazi）。
                    val token = if (zwToken.isNotBlank()) zwToken else bzToken
                    Repo.startReading(
                        question = "请结合命盘，详细解读我的$periodLabel，说明要注意什么，并给出可以先做的具体建议。",
                        contextTokens = listOf(token),
                    )
                },
                modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
            ) { Text(if (started) "重新解读$periodLabel" else "生成$periodLabel 的 AI 解读") }
            Text(
                "点击生成才会调用模型；只发送盘面事实，不发送出生时间或坐标。",
                fontSize = 11.5.sp,
                color = DestinyColors.Muted,
            )
        }
    }
}
