package com.solplum.destiny.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.solplum.destiny.net.StreamPhase
import com.solplum.destiny.net.StreamUiState
import kotlinx.coroutines.delay

// ============ 通用小件 ============

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .width(4.dp)
                .heightIn(min = 16.dp)
                .background(DestinyColors.Accent, RoundedCornerShape(2.dp)),
        )
        Spacer(Modifier.width(8.dp))
        Text(text, fontWeight = FontWeight.Bold, fontSize = 15.sp)
    }
}

@Composable
fun ErrorBar(message: String, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .background(Color0ErrorBg(), RoundedCornerShape(10.dp))
            .border(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.4f), RoundedCornerShape(10.dp))
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("⚠", color = MaterialTheme.colorScheme.error, fontSize = 14.sp)
        Spacer(Modifier.width(6.dp))
        SelectionContainer { Text(message, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
    }
}

private fun Color0ErrorBg() = androidx.compose.ui.graphics.Color(0xFFFDECEC)

@Composable
fun LoadingRow(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(modifier = Modifier.width(18.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(10.dp))
        Text(text, fontSize = 13.sp, color = DestinyColors.Muted)
    }
}

/** 未建档门牌（design-spec §2.3 task-gate 等价物）。 */
@Composable
fun GateCard(title: String, hint: String, buttonText: String, onButton: () -> Unit, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = androidx.compose.foundation.BorderStroke(1.dp, DestinyColors.SoftLine),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Text(hint, fontSize = 13.sp, color = DestinyColors.Muted)
            Button(onClick = onButton) { Text(buttonText, Modifier.heightIn(min = 44.dp)) }
        }
    }
}

@Composable
fun FooterDisclaimer(modifier: Modifier = Modifier) {
    Text(
        "传统命理解释框架，不构成医疗、法律或投资建议。",
        modifier = modifier.fillMaxWidth().padding(vertical = 12.dp),
        fontSize = 12.sp,
        color = DestinyColors.Muted,
    )
}

// ============ Markdown-lite（design-spec §4.2 / contract §8.10）============

private sealed interface MdBlock
private data class MdHeading(val text: String) : MdBlock
private data class MdBullets(val items: List<String>) : MdBlock
private data class MdPara(val text: String) : MdBlock

private val BULLET_PREFIX = Regex("^[-*•]\\s*")
private val NUM_PREFIX = Regex("^\\d+[.、)]\\s*")

private fun parseMarkdownBlocks(text: String): List<MdBlock> {
    val out = mutableListOf<MdBlock>()
    var para = StringBuilder()
    var bullets = mutableListOf<String>()
    fun flushPara() {
        if (para.isNotBlank()) out += MdPara(para.toString().trim())
        para = StringBuilder()
    }
    fun flushBullets() {
        if (bullets.isNotEmpty()) out += MdBullets(bullets.toList())
        bullets = mutableListOf()
    }
    text.lines().forEach { raw ->
        val line = raw.trim()
        when {
            line.isEmpty() -> { flushPara(); flushBullets() }
            line.startsWith("#") -> { flushPara(); flushBullets(); out += MdHeading(line.trimStart('#').trim()) }
            line == "---" || line == "***" || line == "___" -> { flushPara(); flushBullets() }
            BULLET_PREFIX.containsMatchIn(line) || NUM_PREFIX.containsMatchIn(line) -> {
                flushPara()
                bullets += line.replace(BULLET_PREFIX, "").replace(NUM_PREFIX, "")
            }
            else -> {
                flushBullets()
                if (para.isNotEmpty()) para.append('\n')
                para.append(line)
            }
        }
    }
    flushPara()
    flushBullets()
    return out
}

/** 行内 **加粗**；奇数个 ** 时末段按加粗渲染（未闭合容忍，design-spec §4.2 InlineText）。 */
fun boldAnnotated(text: String): AnnotatedString = buildAnnotatedString {
    val parts = text.split("**")
    val unclosed = (parts.size - 1) % 2 == 1
    parts.forEachIndexed { i, p ->
        if (p.isEmpty()) return@forEachIndexed
        if (i % 2 == 1 || (unclosed && i == parts.lastIndex)) {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(p) }
        } else {
            append(p)
        }
    }
}

@Composable
private fun MdHeadingCard(text: String) {
    val isNote = text.contains("注意")
    val bg = if (isNote) DestinyColors.WarnBg else DestinyColors.Wash
    Row(
        Modifier
            .fillMaxWidth()
            .background(bg, RoundedCornerShape(8.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            (if (isNote) "⚠ " else "") + text,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp,
            fontFamily = ReadingFont,
            color = DestinyColors.Ink,
        )
    }
}

@Composable
fun MarkdownLite(text: String, modifier: Modifier = Modifier) {
    val blocks = remember(text) { parseMarkdownBlocks(text) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        blocks.forEach { b ->
            when (b) {
                is MdHeading -> MdHeadingCard(b.text)
                is MdBullets -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    b.items.forEach { item ->
                        Row {
                            Text("• ", fontSize = 14.sp, fontFamily = ReadingFont)
                            Text(
                                boldAnnotated(item),
                                fontSize = 14.sp,
                                fontFamily = ReadingFont,
                                lineHeight = 21.sp,
                            )
                        }
                    }
                }
                is MdPara -> Text(
                    boldAnnotated(b.text),
                    fontSize = 14.5.sp,
                    fontFamily = ReadingFont,
                    lineHeight = 23.sp,
                )
            }
        }
    }
}

// ============ 思考链折叠（design-spec §4.3 ThinkingTrace）============

@Composable
fun ThinkTrace(state: StreamUiState, modifier: Modifier = Modifier) {
    if (state.thinkText.isEmpty()) return
    var expanded by remember { mutableStateOf(false) }
    LaunchedEffect(state.phase) {
        expanded = state.phase == StreamPhase.THINKING
    }
    val scroll = rememberScrollState()
    LaunchedEffect(expanded, state.thinkText.length) {
        if (expanded) scroll.animateScrollTo(scroll.maxValue)
    }
    val thinking = state.phase == StreamPhase.THINKING
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(thinking) {
        while (thinking) {
            nowMs = System.currentTimeMillis()
            delay(1000)
        }
    }
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .border(1.dp, DestinyColors.SoftLine, RoundedCornerShape(10.dp))
            .animateContentSize(),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .background(DestinyColors.Wash.copy(alpha = 0.35f))
                .padding(horizontal = 10.dp, vertical = 8.dp)
                .heightIn(min = 44.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val elapsed = if (state.startedAtMs > 0) ((nowMs - state.startedAtMs) / 1000).coerceAtLeast(0) else 0
            Text(
                if (thinking) "思考中… 已用时 ${elapsed}秒" else "已深度推演 · 点击查看思路",
                color = DestinyColors.Accent,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
            )
            Spacer(Modifier.weight(1f))
            Text(if (expanded) "▾" else "▸", color = DestinyColors.Accent)
        }
        if (expanded) {
            SelectionContainer {
                Text(
                    state.thinkText,
                    Modifier
                        .fillMaxWidth()
                        .heightIn(max = 220.dp)
                        .verticalScroll(scroll)
                        .padding(10.dp),
                    fontSize = 12.5.sp,
                    lineHeight = 19.sp,
                    fontFamily = ReadingFont,
                    color = DestinyColors.Muted,
                )
            }
        }
    }
}

// ============ 流式结果面板（全部 SSE 屏共用）============

@Composable
fun StreamPanel(state: StreamUiState, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ThinkTrace(state)
        state.error?.let { ErrorBar(it) }
        val display = state.fullText.take(state.shown)
        if (display.isNotEmpty()) {
            SelectionContainer { MarkdownLite(display) }
            if (state.shown < state.fullText.length) {
                Text("▌", color = DestinyColors.Accent, fontSize = 14.sp)
            }
        } else if (state.phase == StreamPhase.THINKING) {
            LoadingRow("正在生成解读…")
        }
        if (state.sources.isNotEmpty()) {
            SectionTitle("参考出处")
            state.sources.forEach { s ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(10.dp))
                        .border(1.dp, DestinyColors.SoftLine, RoundedCornerShape(10.dp))
                        .padding(10.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(s.work, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        s.channel?.let { c ->
                            Spacer(Modifier.width(6.dp))
                            Text(
                                c,
                                Modifier
                                    .background(DestinyColors.Wash, RoundedCornerShape(4.dp))
                                    .padding(horizontal = 4.dp, vertical = 1.dp),
                                fontSize = 11.sp,
                            )
                        }
                    }
                    if (s.quote.isNotBlank()) {
                        Text(
                            s.quote,
                            fontSize = 12.5.sp,
                            color = DestinyColors.Muted,
                            fontFamily = ReadingFont,
                        )
                    }
                }
            }
        }
    }
}
