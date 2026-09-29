package com.solplum.destiny.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.solplum.destiny.data.Repo
import com.solplum.destiny.net.StreamBus
import com.solplum.destiny.net.StreamPhase
import com.solplum.destiny.ui.DestinyColors
import com.solplum.destiny.ui.SectionTitle
import com.solplum.destiny.ui.StreamPanel

private val EXAMPLES = listOf(
    "梦见在晴天的湖边散步，水面很平静",
    "梦见回到小学教室考试，找不到座位",
    "梦见房子着火但没有人受伤",
)

@Composable
fun DreamScreen(nav: NavController) {
    var dream by rememberSaveable { mutableStateOf("") }
    var err by remember { mutableStateOf<String?>(null) }
    val streamState by StreamBus.state.collectAsState()
    val busy = streamState.phase == StreamPhase.THINKING || streamState.phase == StreamPhase.STREAMING

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "写下你的梦境（4–2000 字），AI 会结合荣格与传统解梦口径给出流式解读；若涉及自伤等信号，会直接展示转介建议。",
            fontSize = 12.5.sp,
            color = DestinyColors.Muted,
        )

        OutlinedTextField(
            value = dream,
            onValueChange = { if (it.length <= 2000) dream = it },
            label = { Text("梦境描述") },
            supportingText = { Text("${dream.length}/2000") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 4,
        )

        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("试试：", fontSize = 12.sp, color = DestinyColors.Muted)
            EXAMPLES.forEach { e ->
                FilterChip(
                    selected = false,
                    onClick = { dream = e },
                    label = { Text(e, fontSize = 11.5.sp) },
                    colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
                )
            }
        }

        err?.let { Text(it, color = androidx.compose.material3.MaterialTheme.colorScheme.error, fontSize = 13.sp) }

        Button(
            onClick = {
                when {
                    dream.length < 4 -> err = "梦境描述至少 4 个字。"
                    else -> {
                        err = null
                        Repo.startDream(dream.trim())
                    }
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
        ) { Text(if (busy) "解读中…" else if (streamState.phase == StreamPhase.DONE) "再解一次" else "开始解读") }

        SectionTitle("解读")
        StreamPanel(streamState)
    }
}
