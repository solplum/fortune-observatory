package com.solplum.destiny.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.solplum.destiny.data.Repo
import com.solplum.destiny.state.Memory
import com.solplum.destiny.ui.DestinyColors
import com.solplum.destiny.ui.FooterDisclaimer

private data class Entry(val emoji: String, val title: String, val subtitle: String, val route: String)

private val ENTRIES = listOf(
    Entry("☸", "排盘", "八字 · 紫微 · 七政", "chart"),
    Entry("📈", "运势", "今日 / 明日 / 本周 / 本月", "fortune"),
    Entry("💬", "问事", "健康 姻缘 事业 财运", "ask"),
    Entry("🌙", "解梦", "梦象流式解读", "dream"),
    Entry("🧭", "奇门", "遁甲起局与读盘", "qimen"),
    Entry("🌿", "中医", "症状问诊参考", "tcm"),
)

@Composable
fun HomeScreen(nav: NavController) {
    LaunchedEffect(Unit) {
        Memory.aiStatus = (Repo.aiStatus() as? com.solplum.destiny.net.ApiResult.Ok)?.data
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Spacer(Modifier.height(8.dp))
        Text("看运", fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(
            "传统命理计算 + AI 解读；出生资料只在本机使用，计算时会发送到服务器处理。",
            fontSize = 12.5.sp,
            color = DestinyColors.Muted,
        )
        Spacer(Modifier.height(6.dp))
        val status = Memory.aiStatus
        Row(verticalAlignment = Alignment.CenterVertically) {
            val (dot, label) = when {
                status == null -> Color(0xFFB8B4A8) to "AI 解读状态未知"
                status.available -> Color(0xFF2E9E5B) to "AI 解读可用（${status.mode}）"
                else -> Color(0xFFC62828) to "服务端未配置 AI 解读"
            }
            androidx.compose.foundation.layout.Box(
                Modifier
                    .width(8.dp)
                    .aspectRatio(1f)
                    .clip(RoundedCornerShape(4.dp))
                    .background(dot),
            )
            Spacer(Modifier.width(6.dp))
            Text(label, fontSize = 12.5.sp, color = DestinyColors.Muted)
        }
        Spacer(Modifier.height(14.dp))
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.weight(1f).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 16.dp),
        ) {
            items(ENTRIES) { e ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .aspectRatio(1.45f)
                        .clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surface)
                        .border(1.dp, DestinyColors.SoftLine, RoundedCornerShape(14.dp))
                        .clickable { nav.navigate(e.route) }
                        .padding(14.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(e.emoji, fontSize = 30.sp)
                    Spacer(Modifier.height(6.dp))
                    Text(e.title, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Text(e.subtitle, fontSize = 11.5.sp, color = DestinyColors.Muted)
                }
            }
        }
        FooterDisclaimer()
    }
}
