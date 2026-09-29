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
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.font.FontWeight
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
    "长期失眠多梦怎么办",
    "最近总是口干舌燥、容易疲倦",
    "换季就咳嗽，喉咙发痒",
)

@Composable
fun TcmScreen(nav: NavController) {
    var question by rememberSaveable { mutableStateOf("") }
    var err by remember { mutableStateOf<String?>(null) }
    val streamState by StreamBus.state.collectAsState()
    val busy = streamState.phase == StreamPhase.THINKING || streamState.phase == StreamPhase.STREAMING

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "仅供学习，不适请就医。",
            Modifier
                .fillMaxWidth()
                .heightIn(min = 36.dp)
                .padding(top = 4.dp),
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = DestinyColors.Accent2,
        )
        Text(
            "描述症状（4–2000 字），AI 以经方口径给出流式参考；正文末尾的免责声明由服务端保证追加，请完整阅读。",
            fontSize = 12.5.sp,
            color = DestinyColors.Muted,
        )

        OutlinedTextField(
            value = question,
            onValueChange = { if (it.length <= 2000) question = it },
            label = { Text("症状描述") },
            supportingText = { Text("${question.length}/2000") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 4,
        )

        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("试试：", fontSize = 12.sp, color = DestinyColors.Muted)
            EXAMPLES.forEach { e ->
                FilterChip(
                    selected = false,
                    onClick = { question = e },
                    label = { Text(e, fontSize = 11.5.sp) },
                    colors = FilterChipDefaults.filterChipColors(selectedContainerColor = DestinyColors.Wash),
                )
            }
        }

        err?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }

        Button(
            onClick = {
                when {
                    question.length < 4 -> err = "症状描述至少 4 个字。"
                    else -> {
                        err = null
                        Repo.startTcm(question.trim())
                    }
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
        ) { Text(if (busy) "问诊中…" else if (streamState.phase == StreamPhase.DONE) "再问一次" else "开始问诊") }

        SectionTitle("问诊参考")
        StreamPanel(streamState)
    }
}
