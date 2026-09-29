package com.solplum.destiny.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.solplum.destiny.net.StreamBus
import com.solplum.destiny.net.StreamPhase
import com.solplum.destiny.state.AskMemory
import com.solplum.destiny.state.Memory
import com.solplum.destiny.ui.DestinyColors
import com.solplum.destiny.ui.GateCard
import com.solplum.destiny.ui.MarkdownLite
import com.solplum.destiny.ui.SectionTitle
import com.solplum.destiny.ui.StreamPanel

private val DOMAINS = listOf(
    "健康" to "health",
    "姻缘" to "relationship",
    "事业" to "career",
    "财运" to "wealth",
)

@Composable
fun AskScreen(nav: NavController) {
    val chart = Memory.chart
    if (chart == null) {
        Column(Modifier.fillMaxSize().padding(16.dp)) {
            GateCard(
                title = "问事需要先完成一次排盘",
                hint = "领域批解与自由对话都要读取命盘的解读上下文，先去排盘。",
                buttonText = "去排盘",
                onButton = { nav.navigate("chart") },
            )
        }
        return
    }

    var domain by remember { mutableStateOf("自由问") }
    var question by remember { mutableStateOf("") }
    var err by remember { mutableStateOf<String?>(null) }
    // 流面板钉住标志：ERROR 终态时不随落账收起，保证错误文案与已流出正文保持可见
    var streamPanelPinned by remember { mutableStateOf(false) }
    val streamState by StreamBus.state.collectAsState()

    // 流终态落账（design-spec §4.2 收尾落定口径）：
    // DONE -> 全文进历史并收起流面板；ERROR -> 已流出部分正文进历史（safety 清空则为空），
    // 同时清 pendingQuestion 防止会话状态泄漏，面板保持钉住以展示错误原文。
    LaunchedEffect(streamState.phase) {
        if (AskMemory.pendingQuestion != null &&
            (streamState.phase == StreamPhase.DONE || streamState.phase == StreamPhase.ERROR)
        ) {
            AskMemory.commitCurrent(streamState.fullText)
            if (streamState.phase == StreamPhase.DONE) streamPanelPinned = false
        }
    }

    fun tokensFor(dom: String): List<String> {
        val ctx = chart.ai_contexts
        return when {
            dom == "自由问" -> listOfNotNull(ctx["ziwei"]?.token, ctx["bazi"]?.token)
            else -> listOfNotNull(ctx[dom]?.token, ctx["ziwei"]?.token)
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        ) {
            (listOf("自由问") + DOMAINS.map { it.first }).forEach { d ->
                FilterChip(
                    selected = domain == d,
                    onClick = { domain = d },
                    label = { Text(d, Modifier.heightIn(min = 24.dp)) },
                    colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
                )
            }
            Spacer(Modifier.width(4.dp))
            if (AskMemory.turns.isNotEmpty()) {
                TextButton(onClick = { AskMemory.clear(); streamPanelPinned = false }) { Text("新对话") }
            }
        }

        if (tokensFor(domain).isEmpty()) {
            Text(
                "服务端未开放「${if (domain == "自由问") "命盘" else domain}」的解读上下文（ai_contexts 为空），无法发起解读。",
                fontSize = 12.5.sp,
                color = DestinyColors.Muted,
            )
        }

        SectionTitle(if (domain == "自由问") "想问什么" else "${domain}专项批解")

        // 历史对话
        AskMemory.turns.forEachIndexed { idx, turn ->
            val isCurrent = idx == AskMemory.turns.lastIndex && AskMemory.pendingQuestion != null
            if (isCurrent) return@forEachIndexed  // 当前进行中的流由 StreamPanel 呈现
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "问：${turn.question}",
                    Modifier
                        .fillMaxWidth()
                        .background(DestinyColors.Wash.copy(alpha = 0.4f), RoundedCornerShape(10.dp))
                        .padding(10.dp),
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Medium,
                )
                if (turn.answer.isNotEmpty()) {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                        MarkdownLite(turn.answer, Modifier.padding(10.dp))
                    }
                }
            }
        }

        OutlinedTextField(
            value = question,
            onValueChange = { if (it.length <= 300) question = it },
            label = { Text("问题（1–300 字）") },
            supportingText = { Text("${question.length}/300") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 2,
        )
        err?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }

        val busy = streamState.phase == StreamPhase.THINKING || streamState.phase == StreamPhase.STREAMING
        Button(
            onClick = {
                if (question.isBlank()) {
                    err = "请先输入问题。"
                } else {
                    err = null
                    val tokens = tokensFor(domain)
                    if (!Repo.startReading(question.trim(), tokens, AskMemory.turns.map { it.question to it.answer })) {
                        err = "解读上下文不可用，请重新排盘后再试。"
                    } else {
                        AskMemory.startTurn(question.trim())
                        streamPanelPinned = true
                        question = ""
                    }
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
        ) { Text(if (busy) "解读中…" else if (AskMemory.turns.isEmpty()) "问 AI" else "继续追问") }

        if (streamPanelPinned) {
            StreamPanel(streamState)
        }
        Text(
            "点击提问才会调用模型；只发送盘面事实与对话内容，不发送出生时间或坐标。对话最多保留 12 轮上下文。",
            fontSize = 11.5.sp,
            color = DestinyColors.Muted,
        )
    }
}
