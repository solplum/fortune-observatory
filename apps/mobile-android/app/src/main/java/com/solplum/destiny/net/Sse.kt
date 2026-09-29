package com.solplum.destiny.net

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Request
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.coroutineContext
import kotlin.math.max
import kotlin.math.min

data class StreamSource(val work: String, val quote: String, val channel: String? = null)

enum class StreamPhase { IDLE, THINKING, STREAMING, DONE, ERROR }

data class StreamUiState(
    val phase: StreamPhase = StreamPhase.IDLE,
    val fullText: String = "",
    val thinkText: String = "",
    /** 打字机已展示的字符数（design-spec §4.2 displayText 节奏器）。 */
    val shown: Int = 0,
    val error: String? = null,
    val sources: List<StreamSource> = emptyList(),
    val startedAtMs: Long = 0L,
)

/**
 * 进程内单例 SSE 流总线（contract §8.14：同 IP 在途帽 2 条，全局同一时刻只保持 1 条流）。
 * 事件解析对齐 contract §4.1：data 行取 JSON；注释心跳由 okhttp-sse 的 onComment 吞掉；
 * `data: [DONE]` 哨兵行跳过；reading 无哨兵、解梦/奇门/中医有——均以 done/error 事件定终态。
 * 断线重连：静默 EOF/RST -> 清空本地缓冲等全量回放 -> 600ms 后重连，最多 2 次（contract §4.1）。
 */
object StreamBus {

    private const val PACER_STREAM_RATE = 80.0      // 字/秒（design-spec §4.2）
    private const val PACER_DRAIN_RATE = 640.0      // 终态后放完余量
    private const val PACER_FRAME_MS = 33L
    private const val REPLAY_GAP_FAST = 2000        // 回放追赶缺口阈值
    private const val MAX_RECONNECTS = 2
    private const val RECONNECT_DELAY_MS = 600L

    /**
     * 心跳看门狗：服务端空闲 10 秒发一次心跳注释行（契约 §4.1）。连续 2 个心跳周期无任何
     * 数据/注释行到达即视为连接被代理/NAT 静默挂死（无 FIN、无数据），主动取消当前连接
     * 交由重连循环接管（契约 §5.1「>10s 无心跳即视为异常」的工程化容差版）。
     */
    private const val HEARTBEAT_SILENCE_MS = 20_000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(StreamUiState())
    val state: StateFlow<StreamUiState> = _state.asStateFlow()

    private var mainJob: Job? = null
    private var pacerJob: Job? = null

    private val currentSource = AtomicReference<EventSource?>(null)

    @Volatile
    private var lastActivityMs = 0L

    /** 启动一条流（顶替旧流）。[body] 须序列化一次后原样复用（重连续传键要求逐字节一致，contract §8.4）。 */
    fun start(url: String, body: String) {
        mainJob?.cancel()
        pacerJob?.cancel()
        lastActivityMs = System.currentTimeMillis()
        _state.value = StreamUiState(phase = StreamPhase.THINKING, startedAtMs = System.currentTimeMillis())
        mainJob = scope.launch { runWithReconnect(url, body) }
        pacerJob = scope.launch { pacerLoop() }
    }

    fun reset() {
        mainJob?.cancel()
        pacerJob?.cancel()
        mainJob = null
        pacerJob = null
        _state.value = StreamUiState()
    }

    private suspend fun runWithReconnect(url: String, body: String) {
        var attempts = 0
        while (coroutineContext.isActive) {
            val outcome = openOnce(url, body)
            if (outcome == TERMINAL_CLEAN || !coroutineContext.isActive) return
            attempts += 1
            if (attempts > MAX_RECONNECTS) {
                _state.update {
                    it.copy(phase = StreamPhase.ERROR, error = "连接中断，自动重连仍未恢复，请重试。")
                }
                return
            }
            // 服务端重连后会全量回放：清空本地缓冲等待回放（streamReading.ts:179-182 口径）
            _state.update {
                it.copy(phase = StreamPhase.THINKING, fullText = "", thinkText = "", shown = 0, sources = emptyList())
            }
            delay(RECONNECT_DELAY_MS)
        }
    }

    private const val TERMINAL_CLEAN = "clean"
    private const val STREAM_EOF = "eof"

    private suspend fun openOnce(url: String, body: String): String = suspendCancellableCoroutine { cont ->
        val settled = AtomicBoolean(false)
        lastActivityMs = System.currentTimeMillis()
        fun settle(v: String) {
            if (settled.compareAndSet(false, true) && cont.isActive) cont.resume(v) {}
        }
        val request = Request.Builder()
            .url(url)
            .header("accept", "text/event-stream")
            .header("content-type", "application/json")
            .post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
            .build()
        val es = EventSources.createFactory(Http.sseClient).newEventSource(request, object : EventSourceListener() {
            override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                lastActivityMs = System.currentTimeMillis()
                val trimmed = data.trim()
                if (trimmed == "[DONE]") { settle(TERMINAL_CLEAN); return }  // 哨兵行跳过
                // 事件字段解析零信任：形状不符（type/text 为数组/对象等）丢弃该事件，不击穿 OkHttp 线程
                val terminal = runCatching { handleEvent(data) }.getOrDefault(false)
                if (terminal) settle(TERMINAL_CLEAN)
            }

            override fun onClosed(eventSource: EventSource) {
                settle(STREAM_EOF)  // 未收到终态即关流：视为断流，走重连
            }

            override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                val resp = response
                if (resp != null && resp.code >= 300) {
                    // HTTP 层错误（400/413/429/5xx…）：按契约 §4.1 重连仅针对静默 EOF/RST，
                    // §8.2 要求解析 Retry-After 并向用户转述 detail 原文——直接终态，不重连。
                    val bodyText = runCatching { resp.body?.string() }.getOrNull().orEmpty()
                    val err = Http.errorFrom(resp.code, bodyText, resp.header("Retry-After"))
                    _state.update { it.copy(phase = StreamPhase.ERROR, error = err.message) }
                    settle(TERMINAL_CLEAN)
                } else {
                    settle(STREAM_EOF)  // 静默 EOF/RST（response 为空）：走重连
                }
            }
        })
        currentSource.set(es)
        cont.invokeOnCancellation {
            currentSource.compareAndSet(es, null)
            runCatching { es.cancel() }
        }
    }

    /** @return 是否终态事件（done / error）。 */
    private fun handleEvent(data: String): Boolean {
        val obj = runCatching { Api.json.parseToJsonElement(data).jsonObject }.getOrNull() ?: return false
        return when (obj["type"]?.jsonPrimitive?.content) {
            "think" -> {
                obj["text"]?.jsonPrimitive?.content?.let { t ->
                    _state.update { it.copy(thinkText = it.thinkText + t) }
                }
                false
            }
            "delta" -> {
                obj["text"]?.jsonPrimitive?.content?.let { t ->
                    _state.update {
                        it.copy(fullText = it.fullText + t, phase = StreamPhase.STREAMING)
                    }
                }
                false
            }
            "done" -> {
                val sources = parseSources(obj["sources"])
                _state.update { st ->
                    st.copy(phase = StreamPhase.DONE, sources = if (sources.isNotEmpty()) sources else st.sources)
                }
                true
            }
            "error" -> {
                val detail = obj["detail"]?.jsonPrimitive?.content ?: "解读失败，请稍后重试。"
                val code = obj["code"]?.jsonPrimitive?.content
                _state.update { st ->
                    if (code == "safety") {
                        // 内容红线：正文不可信，清空已展示文本（contract §8.6）
                        st.copy(phase = StreamPhase.ERROR, error = detail, fullText = "", thinkText = "", shown = 0)
                    } else {
                        st.copy(phase = StreamPhase.ERROR, error = detail)
                    }
                }
                true
            }
            else -> false
        }
    }

    /** sources 条目形状按「字段存在才渲染」（contract §8.15：解梦有 channel、中医无、奇门无 sources）。 */
    private fun parseSources(el: Any?): List<StreamSource> {
        val arr = el as? JsonArray ?: return emptyList()
        return arr.mapNotNull { item ->
            val o = item as? JsonObject ?: return@mapNotNull null
            val work = (o["work"] as? JsonPrimitive)?.content ?: return@mapNotNull null
            StreamSource(
                work = work,
                quote = (o["quote"] as? JsonPrimitive)?.content.orEmpty(),
                channel = (o["channel"] as? JsonPrimitive)?.content,
            )
        }
    }

    /** 打字机节奏器：流式 80 字/秒、终态或大缺口 640 字/秒（design-spec §4.2）；顺带承担心跳看门狗。 */
    private suspend fun pacerLoop() {
        var last = System.nanoTime()
        while (coroutineContext.isActive) {
            delay(PACER_FRAME_MS)
            val now = System.nanoTime()
            val dt = (now - last) / 1_000_000_000.0
            last = now
            val snap = _state.value
            // 终态且余量已放完：本轮流的节奏与心跳看门狗使命结束，退出循环（勿常驻空转耗电）
            if ((snap.phase == StreamPhase.DONE || snap.phase == StreamPhase.ERROR) &&
                snap.shown >= snap.fullText.length
            ) {
                return
            }
            if ((snap.phase == StreamPhase.THINKING || snap.phase == StreamPhase.STREAMING) &&
                lastActivityMs > 0 && System.currentTimeMillis() - lastActivityMs > HEARTBEAT_SILENCE_MS
            ) {
                // 连接静默挂死：主动取消当前连接，onFailure(response=null) 会走 EOF 重连路径
                currentSource.getAndSet(null)?.cancel()
            }
            _state.update { st ->
                val total = st.fullText.length
                if (st.shown >= total) {
                    st
                } else {
                    val terminal = st.phase == StreamPhase.DONE || st.phase == StreamPhase.ERROR
                    val gap = total - st.shown
                    val rate = if (terminal || gap > REPLAY_GAP_FAST) PACER_DRAIN_RATE else PACER_STREAM_RATE
                    st.copy(shown = min(total, st.shown + max(1.0, rate * dt).toInt()))
                }
            }
        }
    }
}
