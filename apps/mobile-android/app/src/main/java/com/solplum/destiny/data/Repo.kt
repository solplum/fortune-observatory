package com.solplum.destiny.data

import com.solplum.destiny.net.Api
import com.solplum.destiny.net.ApiResult
import com.solplum.destiny.net.Http
import com.solplum.destiny.model.ReadingRequest
import com.solplum.destiny.net.StreamBus
import com.solplum.destiny.model.AiStatusResponse
import com.solplum.destiny.model.BirthRequest
import com.solplum.destiny.model.ChartResponse
import com.solplum.destiny.model.DailyTransitRequest
import com.solplum.destiny.model.DailyTransitResponse
import com.solplum.destiny.model.DreamRequest
import com.solplum.destiny.model.HealthResponse
import com.solplum.destiny.model.QimenChartRequest
import com.solplum.destiny.model.ReadingHistoryItem
import com.solplum.destiny.model.TcmRequest
import com.solplum.destiny.model.TransitResponse
import com.solplum.destiny.model.TransitWindowRequest
import com.solplum.destiny.model.WindowTransitResponse
import kotlinx.serialization.json.JsonObject
import java.security.SecureRandom

/** 生产 API 数据层；SSE 端点走 StreamBus 单例。 */
object Repo {

    private const val READING_HISTORY_MAX_TURNS = 12
    private const val HISTORY_TEXT_MAX = 600
    private const val QUESTION_MAX = 300

    suspend fun health(): ApiResult<HealthResponse> =
        Http.getJsonText("${Api.BASE}/health").map { Api.json.decodeFromString<HealthResponse>(it) }

    suspend fun aiStatus(): ApiResult<AiStatusResponse> =
        Http.getJsonText("${Api.BASE}/v1/ai/status").map { Api.json.decodeFromString<AiStatusResponse>(it) }

    suspend fun charts(birth: BirthRequest): ApiResult<ChartResponse> =
        Http.postJsonText("${Api.BASE}/v1/charts", Api.json.encodeToString(BirthRequest.serializer(), birth))
            .map { Api.json.decodeFromString<ChartResponse>(it) }

    suspend fun dailyTransit(birth: BirthRequest, transitDate: String): ApiResult<DailyTransitResponse> {
        val body = Api.json.encodeToString(DailyTransitRequest.serializer(), DailyTransitRequest(birth, transitDate))
        return Http.postJsonText("${Api.BASE}/v1/transits/daily", body)
            .map { Api.json.decodeFromString<DailyTransitResponse>(it) }
    }

    suspend fun transitWindow(birth: BirthRequest, startDate: String, endDate: String): ApiResult<WindowTransitResponse> {
        val body = Api.json.encodeToString(
            TransitWindowRequest.serializer(),
            TransitWindowRequest(birth, startDate, endDate),
        )
        return Http.postJsonText("${Api.BASE}/v1/transits/window", body)
            .map { Api.json.decodeFromString<WindowTransitResponse>(it) }
    }

    /** 时间层事实（契约 §3.4，端点 #6）；请求体同 daily（{birth, transit_date}）。 */
    suspend fun transits(birth: BirthRequest, transitDate: String): ApiResult<TransitResponse> {
        val body = Api.json.encodeToString(DailyTransitRequest.serializer(), DailyTransitRequest(birth, transitDate))
        return Http.postJsonText("${Api.BASE}/v1/transits", body)
            .map { Api.json.decodeFromString<TransitResponse>(it) }
    }

    suspend fun qimenChart(request: QimenChartRequest): ApiResult<JsonObject> {
        val body = Api.json.encodeToString(QimenChartRequest.serializer(), request)
        return Http.postJsonText("${Api.BASE}/v1/qimen/chart", body).map { raw ->
            Api.json.parseToJsonElement(raw) as? JsonObject
                ?: error("奇门起局响应不是 JSON 对象")
        }
    }

    // ============ SSE 流（POST /v1/ai/reading、解梦、奇门读盘、中医问诊）============

    /**
     * 问事/运势流式解读。token 为空时绝不发请求（contract §8.8）。
     * body 序列化一次后由 StreamBus 原样复用，保证重连续传键逐字节一致。
     */
    fun startReading(
        question: String,
        contextTokens: List<String>,
        history: List<Pair<String, String>> = emptyList(),
    ): Boolean {
        val tokens = contextTokens.filter { it.isNotBlank() }.distinct().take(4)
        if (tokens.isEmpty()) return false
        val q = question.take(QUESTION_MAX)
        val hist = history.takeLast(READING_HISTORY_MAX_TURNS)
            .map { (role, text) -> ReadingHistoryItem(role, text.take(HISTORY_TEXT_MAX)) }
        val req = ReadingRequest(
            question = q,
            split_questions = emptyList(),
            context_tokens = tokens,
            history = hist,
            stream_key = newStreamKey(),
        )
        val body = Api.json.encodeToString(ReadingRequest.serializer(), req)
        StreamBus.start("${Api.BASE}/v1/ai/reading", body)
        return true
    }

    fun startDream(dream: String) {
        val body = Api.json.encodeToString(DreamRequest.serializer(), DreamRequest(dream))
        StreamBus.start("${Api.BASE}/v1/dreams/interpret/stream", body)
    }

    fun startQimenInterpret(chartJson: JsonObject) {
        // 契约 §4.5：{"chart": <起局响应原样回传>}，extra=forbid —— 用原始 JsonElement 往返避免形状漂移
        val wrapped = Api.json.encodeToString(
            kotlinx.serialization.json.JsonObject.serializer(),
            kotlinx.serialization.json.buildJsonObject { put("chart", chartJson) },
        )
        StreamBus.start("${Api.BASE}/v1/qimen/interpret/stream", wrapped)
    }

    fun startTcm(question: String) {
        val body = Api.json.encodeToString(TcmRequest.serializer(), TcmRequest(question))
        StreamBus.start("${Api.BASE}/v1/tcm/consult/stream", body)
    }

    private val random = SecureRandom()

    /** stream_key：8-80 字符、[a-zA-Z0-9._-]（contract §4.2）。 */
    private fun newStreamKey(): String {
        val bytes = ByteArray(6)
        random.nextBytes(bytes)
        val hex = bytes.joinToString("") { "%02x".format(it) }
        return "m1.$hex"
    }

    private inline fun <T, R> ApiResult<T>.map(transform: (T) -> R): ApiResult<R> = when (this) {
        is ApiResult.Ok -> ApiResult.Ok(transform(data))
        is ApiResult.Err -> this
    }
}
