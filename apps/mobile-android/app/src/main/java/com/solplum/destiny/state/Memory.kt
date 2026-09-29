package com.solplum.destiny.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.solplum.destiny.model.AiStatusResponse
import com.solplum.destiny.model.BirthRequest
import com.solplum.destiny.model.ChartResponse
import com.solplum.destiny.model.ContextBundle

/**
 * 进程内记忆（v1 明确不做本地偏好持久化；对齐 Web「无账号、档案只存本机」语义的内存版）。
 */
object Memory {
    var birth: BirthRequest? = null

    var chart by mutableStateOf<ChartResponse?>(null)
    var aiStatus by mutableStateOf<AiStatusResponse?>(null)

    /** 最近一次运势响应携带的解读上下文（contract §3.2：ai_context 紫微口径 / ai_context_bazi 八字口径，可空）。 */
    var lastZiweiContext by mutableStateOf<ContextBundle?>(null)
    var lastBaziContext by mutableStateOf<ContextBundle?>(null)

    fun applyChart(b: BirthRequest, c: ChartResponse) {
        birth = b
        chart = c
    }
}

/** 问事（自由对话）的会话历史（内存，≤12 轮回传，契约 §4.2）。 */
object AskMemory {
    class Turn(val question: String, answer: String) {
        /** 可观察状态：AskScreen 直接读本字段渲染气泡，落账赋值必须能触发重组。 */
        var answer by mutableStateOf(answer)
    }

    val turns = mutableStateListOf<Turn>()

    /** 当前流结束后待提交的问题（防止重复落账）。 */
    var pendingQuestion: String? = null

    fun startTurn(question: String) {
        pendingQuestion = question
        turns.add(Turn(question, ""))
        while (turns.size > 20) turns.removeAt(0)
    }

    fun commitCurrent(answer: String) {
        if (pendingQuestion != null && turns.isNotEmpty()) {
            turns.last().answer = answer
        }
        pendingQuestion = null
    }

    fun clear() {
        turns.clear()
        pendingQuestion = null
    }
}
