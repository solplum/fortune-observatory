package com.solplum.destiny.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.solplum.destiny.model.BirthRequest
import com.solplum.destiny.model.ChartResponse
import com.solplum.destiny.model.GanZhi
import com.solplum.destiny.net.ApiResult
import com.solplum.destiny.data.Repo
import com.solplum.destiny.state.Memory
import com.solplum.destiny.ui.DestinyColors
import com.solplum.destiny.ui.ErrorBar
import com.solplum.destiny.ui.LoadingRow
import com.solplum.destiny.ui.ReadingFont
import com.solplum.destiny.ui.SectionTitle
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

private const val TZ = "Asia/Shanghai"

/** 日历存在性校验（2 月 30 日等），避免 ZonedDateTime.of 抛异常崩溃。 */
private fun dateExists(y: Int?, mo: Int?, d: Int?): Boolean =
    y != null && mo != null && d != null && runCatching { LocalDate.of(y, mo, d) }.isSuccess

@Composable
fun ChartScreen(nav: NavController) {
    val chart = Memory.chart
    var editing by rememberSaveable(chart != null) { mutableStateOf(chart == null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
        if (chart == null || editing) {
            ChartForm(
                onSubmitDone = { editing = false },
                hasExisting = chart != null,
            )
        } else {
            ChartResult(chart)
        }
        Spacer(Modifier.height(16.dp))
    }
}

// ============ 排盘表单（contract §3.1 BirthInput）============

@Composable
private fun ChartForm(onSubmitDone: () -> Unit, hasExisting: Boolean) {
    var year by rememberSaveable { mutableStateOf("2000") }
    var month by rememberSaveable { mutableStateOf("1") }
    var day by rememberSaveable { mutableStateOf("1") }
    var hour by rememberSaveable { mutableStateOf("8") }
    var minute by rememberSaveable { mutableStateOf("30") }
    var male by rememberSaveable { mutableStateOf(true) }
    var apparent by rememberSaveable { mutableStateOf(true) }
    var longitude by rememberSaveable { mutableStateOf("104.065") }
    var latitude by rememberSaveable { mutableStateOf("30.659") }
    var err by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    @Composable
    fun fieldRow(label: String, value: String, onChange: (String) -> Unit, width: Int = 90) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, fontSize = 13.sp, modifier = Modifier.width(56.dp))
            TextField(
                value = value,
                onValueChange = onChange,
                singleLine = true,
                modifier = Modifier.width(width.dp).heightIn(min = 52.dp),
            )
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle("出生时间（公历，24 小时制）")
        fieldRow("年", year, { year = it }, 110)
        fieldRow("月", month, { month = it })
        fieldRow("日", day, { day = it })
        fieldRow("时", hour, { hour = it })
        fieldRow("分", minute, { minute = it })

        SectionTitle("性别（用于起运方向等规则）")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = male,
                onClick = { male = true },
                label = { Text("男", Modifier.heightIn(min = 24.dp)) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
            )
            FilterChip(
                selected = !male,
                onClick = { male = false },
                label = { Text("女", Modifier.heightIn(min = 24.dp)) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
            )
        }

        SectionTitle("出生地经纬度（默认成都）")
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TextField(
                value = longitude,
                onValueChange = { longitude = it },
                label = { Text("经度") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            TextField(
                value = latitude,
                onValueChange = { latitude = it },
                label = { Text("纬度") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("真太阳时（推荐）", fontSize = 13.sp, fontWeight = FontWeight.Medium)
                Text("按经度与天文年历换算，Web 端同口径", fontSize = 11.5.sp, color = DestinyColors.Muted)
            }
            Switch(checked = apparent, onCheckedChange = { apparent = it })
        }

        Text(
            "出生资料只存在这台设备上。排盘和运势计算时会发到服务器处理，用完不保存；点生成讲解才会把盘面事实发给 AI 服务商。",
            fontSize = 11.5.sp,
            color = DestinyColors.Muted,
        )

        err?.let { ErrorBar(it) }
        if (loading) LoadingRow("正在排盘…")

        Button(
            onClick = {
                val y = year.toIntOrNull(); val mo = month.toIntOrNull(); val d = day.toIntOrNull()
                val h = hour.toIntOrNull(); val mi = minute.toIntOrNull()
                val lon = longitude.toDoubleOrNull(); val lat = latitude.toDoubleOrNull()
                when {
                    y == null || y !in 1849..2150 -> err = "年份须在 1849–2150 之间。"
                    mo == null || mo !in 1..12 -> err = "月份须在 1–12 之间。"
                    d == null || d !in 1..31 -> err = "日期须在 1–31 之间。"
                    !dateExists(y, mo, d) -> err = "该日期不存在，请检查。"
                    h == null || h !in 0..23 -> err = "小时须在 0–23 之间。"
                    mi == null || mi !in 0..59 -> err = "分钟须在 0–59 之间。"
                    lon == null || lon !in -180.0..180.0 -> err = "经度须在 -180 到 180 之间。"
                    lat == null || lat !in -90.0..90.0 -> err = "纬度须在 -90 到 90 之间。"
                    else -> {
                        err = null
                        // 契约 §3.1：civil_datetime 必须带显式 UTC 偏移且与 timezone_id 在该时刻一致（否则 422）；
                        // §8.12：1986-1991 中国夏令时实际偏移 +09:00。用 tzdb 真实偏移构造：
                        // 重叠段（秋季拨慢）取较早偏移——Web App.tsx:503-509 双偏移候选法之一；空缺段 java.time 自动前移。
                        val zdt = ZonedDateTime.of(y, mo, d, h, mi, 0, 0, ZoneId.of(TZ)).withEarlierOffsetAtOverlap()
                        // Locale.ROOT：%d 按设备地区本地化数字（阿拉伯数字系统会产出非 ASCII 数字，服务端必 422）
                        val civil = "%04d-%02d-%02dT%02d:%02d:00%s".format(java.util.Locale.ROOT, y, mo, d, h, mi, zdt.offset.toString())
                        val birth = BirthRequest(
                            civil_datetime = civil,
                            timezone_id = TZ,
                            longitude = lon,
                            latitude = lat,
                            sex_for_rule = if (male) "male" else "female",
                            use_apparent_solar_time = apparent,
                        )
                        loading = true
                        scope.launch {
                            when (val r = Repo.charts(birth)) {
                                is ApiResult.Ok -> {
                                    Memory.applyChart(birth, r.data)
                                    onSubmitDone()
                                }
                                is ApiResult.Err -> err = r.message
                            }
                            loading = false
                        }
                    }
                }
            },
            enabled = !loading,
            modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
        ) { Text(if (hasExisting) "重新排盘" else "开始排盘") }
    }
}

// ============ 结果页：三盘 Tab（design-spec §4.1）============

@Composable
private fun ChartResult(chart: ChartResponse) {
    var tab by remember { mutableIntStateOf(0) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val trace = chart.time_trace
        Text(
            buildString {
                append("农历 ")
                append(chart.bazi.lunar_date.ifEmpty { "—" })
                trace?.let {
                    append(" · 真太阳时 ")
                    append(it.apparent_solar_datetime.take(16).replace('T', ' '))
                }
            },
            fontSize = 12.5.sp,
            color = DestinyColors.Muted,
        )
        TabRow(selectedTabIndex = tab) {
            listOf("八字四柱", "紫微十二宫", "七政四余").forEachIndexed { i, t ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(t) })
            }
        }
        when (tab) {
            0 -> BaziTab(chart)
            1 -> ZiweiTab(chart)
            else -> QizhengTab(chart)
        }
        InsightsSection(chart)
    }
}

// ---- 盘一 · 四柱八字 ----

@Composable
private fun BaziTab(chart: ChartResponse) {
    val bazi = chart.bazi
    val pillars = listOf(bazi.pillars.year, bazi.pillars.month, bazi.pillars.day, bazi.pillars.hour)
    val labels = listOf("年柱", "月柱", "日柱", "时柱")
    val details = bazi.pillar_details

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionTitle("四柱八字")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                labels.forEach { Text(it, fontSize = 12.sp, color = DestinyColors.Muted) }
            }
            PillarCharRow("天干", pillars) { it.getOrNull(0)?.let { c -> GanZhi.colorOfChar(c) } }
            PillarCharRow("地支", pillars) { it.getOrNull(1)?.let { c -> GanZhi.colorOfChar(c) } }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                labels.forEachIndexed { i, _ ->
                    val tenGod = details.getOrNull(i)?.ten_god ?: "—"
                    Text(tenGod, fontSize = 12.sp, color = DestinyColors.Muted)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                labels.forEachIndexed { i, _ ->
                    val hidden = details.getOrNull(i)?.hidden_stems.orEmpty()
                    Text(
                        hidden.joinToString(" ") { "${it.stem}·${it.ten_god ?: ""}" }.ifEmpty { "—" },
                        fontSize = 11.sp,
                        color = DestinyColors.Muted,
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                labels.forEachIndexed { i, _ ->
                    Text(details.getOrNull(i)?.nayin ?: "—", fontSize = 11.sp, fontFamily = ReadingFont)
                }
            }
            Spacer(Modifier.height(4.dp))
            SectionTitle("五行分布")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GanZhi.fiveElementCounts(pillars.filter { it.length == 2 }).forEach { (el, n) ->
                    Text(
                        "$el$n",
                        Modifier
                            .background(GanZhi.elementColor(el).copy(alpha = 0.12f), RoundedCornerShape(6.dp))
                            .border(1.dp, GanZhi.elementColor(el).copy(alpha = 0.4f), RoundedCornerShape(6.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                        color = GanZhi.elementColor(el),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }
            bazi.great_luck_start?.let { gs ->
                Text(
                    "出生后 ${gs.years}年${gs.months}个月${gs.days}天起运 · ${if (gs.direction == "forward") "顺行" else "逆行"} · 首运 ${gs.first_pillar}",
                    fontSize = 12.5.sp,
                    color = DestinyColors.Muted,
                )
            }
            SectionTitle("大运（前 8 步）")
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                bazi.great_luck_periods.take(8).forEach { p ->
                    Column(
                        Modifier
                            .background(DestinyColors.Wash.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text("${p.start_age}~${p.end_age}岁", fontSize = 11.sp, color = DestinyColors.Muted)
                        Text(p.pillar, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
            Text(
                "紫微定位：命宫在${chart.ziwei.life_branch} · 身宫在${chart.ziwei.body_branch} · 五行局${chart.ziwei.five_elements_bureau}局",
                fontSize = 12.5.sp,
                color = DestinyColors.Muted,
            )
        }
    }
}

@Composable
private fun PillarCharRow(label: String, pillars: List<String>, colorOf: (String) -> androidx.compose.ui.graphics.Color?) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 11.sp, color = DestinyColors.Muted, modifier = Modifier.width(32.dp))
        Spacer(Modifier.weight(0.04f))
        pillars.forEach { p ->
            Text(
                p.take(1).ifEmpty { "—" },
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = colorOf(p) ?: DestinyColors.Ink,
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

// ---- 盘二 · 紫微十二宫 ----

@Composable
private fun ZiweiTab(chart: ChartResponse) {
    val zw = chart.ziwei
    val mutagenOf = remember(zw.birth_mutagens) { zw.birth_mutagens.associate { it.star to it.mutagen } }
    val brightOf = remember(zw.palaces) {
        zw.palaces.flatMap { it.major_star_brightness }.associate { (it.getOrNull(0) ?: "") to (it.getOrNull(1) ?: "") }
    }
    val palaces = zw.palaces.sortedBy { GanZhi.branchIndex(it.branch) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            "命宫${zw.life_branch} · 身宫${zw.body_branch} · ${zw.five_elements_bureau}局 · 生年四化：" +
                zw.birth_mutagens.joinToString("、") { "${it.star}${it.mutagen}" }.ifEmpty { "—" },
            fontSize = 12.5.sp,
            color = DestinyColors.Muted,
        )
        palaces.chunked(3).forEach { rowPalaces ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                rowPalaces.forEach { palace ->
                    Column(
                        Modifier
                            .weight(1f)
                            .heightIn(min = 108.dp)
                            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(10.dp))
                            .border(
                                if (palace.is_body_palace) 2.dp else 1.dp,
                                if (palace.is_body_palace) DestinyColors.Accent2 else DestinyColors.SoftLine,
                                RoundedCornerShape(10.dp),
                            )
                            .padding(6.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(palace.name, fontSize = 12.5.sp, fontWeight = FontWeight.Bold)
                            if (palace.is_body_palace) {
                                Text(
                                    "身",
                                    Modifier
                                        .background(DestinyColors.Accent2, RoundedCornerShape(3.dp))
                                        .padding(horizontal = 3.dp),
                                    color = androidx.compose.ui.graphics.Color.White,
                                    fontSize = 9.sp,
                                )
                            }
                            Spacer(Modifier.weight(1f))
                            Text("${palace.stem}${palace.branch}", fontSize = 11.sp, color = DestinyColors.Muted)
                        }
                        if (palace.major_stars.isEmpty() && palace.minor_stars.isEmpty()) {
                            Text("空宫", fontSize = 11.sp, color = DestinyColors.Muted)
                        }
                        palace.major_stars.forEach { star ->
                            val badge = mutagenOf[star]
                            val bright = brightOf[star]
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(star, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                                bright?.let { Text(it, fontSize = 10.sp, color = DestinyColors.Muted) }
                                badge?.let {
                                    Text(
                                        it,
                                        Modifier
                                            .background(DestinyColors.Wash, RoundedCornerShape(3.dp))
                                            .padding(horizontal = 3.dp),
                                        fontSize = 9.sp,
                                        fontWeight = FontWeight.Bold,
                                    )
                                }
                            }
                        }
                        palace.minor_stars.forEach { star ->
                            Text(star, fontSize = 11.5.sp, color = DestinyColors.Muted)
                        }
                        palace.decadal_range.takeIf { it.size == 2 }?.let {
                            Text("${it[0]}–${it[1]}", fontSize = 10.sp, color = DestinyColors.Muted)
                        }
                    }
                }
                repeat(3 - rowPalaces.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

// ---- 盘三 · 七政四余 ----

@Composable
private fun QizhengTab(chart: ChartResponse) {
    val trad = chart.qizheng.traditional
    if (trad == null) {
        Text("服务端未返回七政四余传统层。", color = DestinyColors.Muted, fontSize = 13.sp)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            "命主${GanZhi.lordName(trad.life_lord)} · 身主${GanZhi.lordName(trad.body_lord)} · " +
                (if (trad.is_day_chart) "昼盘" else "夜盘") +
                " · 童限 ${trad.childhood_exit_age} 岁前",
            fontSize = 12.5.sp,
            color = DestinyColors.Muted,
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SectionTitle("星曜入宿")
                trad.bodies.forEach { b ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            GanZhi.qizhengBodyName(b.body),
                            Modifier.width(52.dp),
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            buildString {
                                append("入${b.mansion ?: "—"}宿")
                                b.mansion_branch?.let { append("（$it 宫）") }
                                append(" · 黄经 ${b.longitude_deg.toInt()}°")
                                append(" · ${GanZhi.motionText(b.motion)}")
                                b.dignity?.let { append(" · $it") }
                                b.relation?.let { append("（$it）") }
                            },
                            fontSize = 12.sp,
                            color = DestinyColors.Muted,
                            fontFamily = ReadingFont,
                        )
                    }
                }
            }
        }
        if (trad.limit_rows.isNotEmpty()) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    SectionTitle("洞微大限 · 行限表")
                    trad.limit_rows.forEach { r ->
                        Text(
                            "${r.palace}（${r.branch}） ${r.start_age}~${r.end_age}岁 · ${r.years.toInt()}年/${r.segment}",
                            fontSize = 12.sp,
                            color = DestinyColors.Muted,
                        )
                    }
                }
            }
        }
        trad.houses?.let { h ->
            Text(
                "十二宫：${h.houses.joinToString("、") { "${it.getOrNull(0) ?: ""}${it.getOrNull(1) ?: ""}" }}",
                fontSize = 12.sp,
                color = DestinyColors.Muted,
            )
        }
    }
}

@Composable
private fun InsightsSection(chart: ChartResponse) {
    if (chart.natal_insights.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle("本命解读")
        chart.natal_insights.forEachIndexed { i, ins ->
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${i + 1}. ${ins.title}", fontWeight = FontWeight.Bold, fontSize = 13.5.sp)
                    Text(ins.summary, fontSize = 12.5.sp, fontFamily = ReadingFont, lineHeight = 19.sp)
                    if (ins.action.isNotBlank()) {
                        Text(
                            "可以先做：${ins.action}",
                            fontSize = 12.sp,
                            color = DestinyColors.Accent,
                        )
                    }
                }
            }
        }
    }
}
