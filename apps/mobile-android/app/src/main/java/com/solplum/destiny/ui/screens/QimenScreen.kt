package com.solplum.destiny.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.solplum.destiny.data.Repo
import com.solplum.destiny.model.QimenChartRequest
import com.solplum.destiny.net.ApiResult
import com.solplum.destiny.net.StreamBus
import com.solplum.destiny.net.StreamPhase
import com.solplum.destiny.ui.DestinyColors
import com.solplum.destiny.ui.ErrorBar
import com.solplum.destiny.ui.LoadingRow
import com.solplum.destiny.ui.SectionTitle
import com.solplum.destiny.ui.StreamPanel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private val QUESTION_TYPES = listOf("事业", "求财", "感情", "学业", "健康", "出行", "诉讼", "寻人寻物", "其他")

// ---- JsonObject 安全取值（契约 §4.4 字段均为可选缺省）----
private fun JsonObject.s(key: String): String = (this[key] as? JsonPrimitive)?.content ?: ""
private fun JsonObject.o(key: String): JsonObject? = this[key] as? JsonObject
private fun JsonObject.a(key: String): JsonArray? = this[key] as? JsonArray

@Composable
fun QimenScreen(nav: NavController) {
    var chartJson by remember { mutableStateOf<JsonObject?>(null) }
    var err by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val streamState by StreamBus.state.collectAsState()

    var qType by rememberSaveable { mutableStateOf("事业") }
    var goal by rememberSaveable { mutableStateOf("") }
    var customTime by rememberSaveable { mutableStateOf(false) }
    var timeInput by rememberSaveable { mutableStateOf("") }
    var city by rememberSaveable { mutableStateOf("") }
    var detailed by rememberSaveable { mutableStateOf(false) }
    var typeMenuOpen by remember { mutableStateOf(false) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SectionTitle("问什么")
        Box {
            OutlinedTextField(
                value = qType,
                onValueChange = {},
                readOnly = true,
                label = { Text("事项类型") },
                trailingIcon = { TextButton(onClick = { typeMenuOpen = !typeMenuOpen }) { Text(if (typeMenuOpen) "▲" else "▼") } },
                modifier = Modifier.fillMaxWidth(),
            )
            DropdownMenu(expanded = typeMenuOpen, onDismissRequest = { typeMenuOpen = false }) {
                QUESTION_TYPES.forEach { t ->
                    DropdownMenuItem(text = { Text(t) }, onClick = { qType = t; typeMenuOpen = false })
                }
            }
        }

        OutlinedTextField(
            value = goal,
            onValueChange = { if (it.length <= 120) goal = it },
            label = { Text("问事目标（2–120 字）") },
            supportingText = { Text("${goal.length}/120") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 2,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = !customTime,
                onClick = { customTime = false },
                label = { Text("就现在", Modifier.heightIn(min = 24.dp)) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
            )
            FilterChip(
                selected = customTime,
                onClick = { customTime = true },
                label = { Text("指定时间", Modifier.heightIn(min = 24.dp)) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
            )
        }
        if (customTime) {
            OutlinedTextField(
                value = timeInput,
                onValueChange = { timeInput = it },
                label = { Text("起局时间（如 2026-10-01 10:00）") },
                supportingText = { Text("≤32 字符；Web 端同款格式（空格分隔）") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        OutlinedTextField(
            value = city,
            onValueChange = { if (it.length <= 40) city = it },
            label = { Text("所在城市（可空）") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = !detailed,
                onClick = { detailed = false },
                label = { Text("简明结论", Modifier.heightIn(min = 24.dp)) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
            )
            FilterChip(
                selected = detailed,
                onClick = { detailed = true },
                label = { Text("详细讲解", Modifier.heightIn(min = 24.dp)) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
            )
        }

        err?.let { ErrorBar(it) }
        if (loading) LoadingRow("正在起局…")

        Button(
            onClick = {
                val g = goal.trim()
                if (g.length < 2) {
                    err = "问事目标至少 2 个字。"
                } else if (customTime && timeInput.isBlank()) {
                    err = "指定时间模式下必须填写起局时间。"
                } else {
                    err = null
                    loading = true
                    scope.launch {
                        when (val r = Repo.qimenChart(QimenChartRequest(
                            question_type = qType,
                            question_goal = g,
                            time_mode = if (customTime) "custom" else "now",
                            time_input = if (customTime) timeInput.trim().take(32).replace('T', ' ') else null,
                            city = city.trim(),
                            detail_level = if (detailed) "detailed" else "brief",
                        ))) {
                            is ApiResult.Ok -> chartJson = r.data
                            is ApiResult.Err -> err = r.message
                        }
                        loading = false
                    }
                }
            },
            enabled = !loading,
            modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
        ) { Text(if (chartJson == null) "起局" else "重新起局") }

        chartJson?.let { json ->
            QimenChartCard(json)
            val busy = streamState.phase == StreamPhase.THINKING || streamState.phase == StreamPhase.STREAMING
            Button(
                onClick = { Repo.startQimenInterpret(json) },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
            ) { Text(if (busy) "读盘中…" else "AI 读盘") }
            Text(
                "点击读盘才会调用模型；整张盘面会原样回传给解读服务。",
                fontSize = 11.5.sp,
                color = DestinyColors.Muted,
            )
            StreamPanel(streamState)
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun QimenChartCard(json: JsonObject) {
    val chart = json.o("chart")
    val gz = json.o("ganzhi")
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "${json.s("question_type")} · ${json.s("question_goal")}",
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                )
                val lunar = json.o("calendar_lunar")
                Text(
                    buildString {
                        append("公历 ")
                        append(json.s("calendar_solar"))
                        if (lunar != null) {
                            append(" · 农历 ")
                            append(lunar.s("month_text"))
                            append(lunar.s("day_text"))
                        }
                        json.o("jieqi")?.let { append(" · 节气 ${it.s("active_jie")}") }
                    },
                    fontSize = 12.sp,
                    color = DestinyColors.Muted,
                )
                if (gz != null) {
                    Text(
                        "四柱 ${gz.s("year")} ${gz.s("month")} ${gz.s("day")} ${gz.s("time")}",
                        fontSize = 13.sp,
                    )
                    Text(
                        buildString {
                            append("旬首 ${gz.s("day_xun_exact")}")
                            append(" · 空亡 ${gz.s("day_xunkong_exact")}")
                        },
                        fontSize = 12.5.sp,
                        color = DestinyColors.Muted,
                    )
                }
                chart?.let { c ->
                    val zhifu = c.o("zhifu"); val zhishi = c.o("zhishi"); val yima = c.o("yima")
                    val dayStem = c.o("day_stem")
                    Text(
                        buildString {
                            zhifu?.let { append("值符 ${it.s("star")}(宫${it.s("palace")})  ") }
                            zhishi?.let { append("值使 ${it.s("door")}(宫${it.s("palace")})") }
                        },
                        fontSize = 12.5.sp,
                        color = DestinyColors.Muted,
                    )
                    Text(
                        buildString {
                            append("遁${c.s("dun_type")}${c.s("ju_number")}局 ${c.s("yuan")}")
                            append(" · 隐干 ${c.s("hidden_yi")}")
                            dayStem?.let { append(" · 日干${it.s("stem")}落宫${it.s("palace")}") }
                            yima?.let { append(" · 驿马${it.s("branch")}在宫${it.s("palace")}") }
                        },
                        fontSize = 12.5.sp,
                        color = DestinyColors.Muted,
                    )
                    c.a("detected_patterns")?.forEach { p ->
                        val po = p as? JsonObject ?: return@forEach
                        val ji = po.s("nature") == "吉"
                        Text(
                            "格局：${po.s("name")}（宫${po.s("palace")}·${po.s("nature")}）",
                            Modifier
                                .background(
                                    if (ji) DestinyColors.GoodBg else DestinyColors.WarnBg,
                                    RoundedCornerShape(6.dp),
                                )
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                            fontSize = 12.sp,
                        )
                    }
                }
            }
        }

        SectionTitle("九宫盘面")
        val gridOrder = chart?.a("grid_order")
            ?.mapNotNull { (it as? JsonPrimitive)?.content?.toIntOrNull() }
            ?: listOf(4, 9, 2, 3, 5, 7, 8, 1, 6)
        val palaceMap = chart?.a("palaces")
            ?.mapNotNull { it as? JsonObject }
            ?.associateBy { (it["palace"] as? JsonPrimitive)?.content?.toIntOrNull() ?: -1 }
            ?: emptyMap()
        gridOrder.chunked(3).forEach { rowIds ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                rowIds.forEach { id ->
                    val p = palaceMap[id]
                    QimenCell(id, p, Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun QimenCell(id: Int, p: JsonObject?, modifier: Modifier = Modifier) {
    Column(
        modifier
            .aspectRatio(0.82f)
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(10.dp))
            .border(1.dp, DestinyColors.SoftLine, RoundedCornerShape(10.dp))
            .padding(6.dp),
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        if (p == null) {
            Text("宫$id", fontSize = 12.sp, color = DestinyColors.Muted)
            Text("中五宫", fontSize = 10.sp, color = DestinyColors.Muted)
            return@Column
        }
        val isCenter = (p["is_center"] as? JsonPrimitive)?.content == "true"
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("${p.s("name")}${p.s("direction")}", fontSize = 11.5.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            if (isCenter) Text("中", fontSize = 10.sp, color = DestinyColors.Accent2)
        }
        val sky = p.s("sky_stem"); val earth = p.s("earth_stem")
        if (sky.isNotEmpty() || earth.isNotEmpty()) {
            Text("天$sky 地$earth", fontSize = 12.5.sp, fontWeight = FontWeight.Medium)
        }
        val star = p.s("star"); val door = p.s("door"); val god = p.s("god")
        if (star.isNotEmpty()) Text(star, fontSize = 11.sp, color = DestinyColors.Muted)
        if (door.isNotEmpty()) Text(door, fontSize = 11.sp, color = DestinyColors.Muted)
        if (god.isNotEmpty()) Text(god, fontSize = 11.sp, color = DestinyColors.Accent)
    }
}

private val JsonPrimitive.isBooleanOrNull: Boolean
    get() = this.content == "true" || this.booleanValueOrNull

private val JsonPrimitive.booleanValueOrNull: Boolean
    get() = runCatching { this.content.toBooleanStrict() }.getOrDefault(false)
