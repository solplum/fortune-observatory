package com.solplum.destiny.net

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** API 基址与 JSON 配置：全部端点收敛在这一处（契约 §0）。 */
object Api {
    const val BASE = "https://destiny.solplum.com/api"

    val json: Json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
        isLenient = true
    }
}

sealed interface ApiResult<out T> {
    data class Ok<T>(val data: T) : ApiResult<T>
    data class Err(
        val message: String,
        val code: Int = 0,
        val retryAfterSeconds: Int? = null,
    ) : ApiResult<Nothing>
}

/** JSON HTTP 客户端（确定性端点 20s 读超时，契约 §5.1）；[sseClient] 供 SSE 专用（不设读超时）。 */
object Http {
    private val jsonClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .build()

    val sseClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .build()

    private const val JSON_TYPE = "application/json; charset=utf-8"

    suspend fun getJsonText(url: String): ApiResult<String> = execute(jsonClient, requestBuilder(url).get().build())

    suspend fun postJsonText(url: String, body: String): ApiResult<String> =
        execute(jsonClient, requestBuilder(url).post(body.toRequestBody(JSON_TYPE)).build())

    private fun requestBuilder(url: String): Request.Builder =
        Request.Builder().url(url).header("accept", "application/json")

    private fun String.toRequestBody(type: String) =
        okhttp3.RequestBody.create(type.toMediaType(), this)

    private suspend fun execute(client: OkHttpClient, request: Request): ApiResult<String> =
        withContext(Dispatchers.IO) {
            val call = client.newCall(request)
            try {
                val response = call.await()
                response.use { resp ->
                    val text = resp.body?.string().orEmpty()
                    if (resp.isSuccessful) {
                        ApiResult.Ok(text)
                    } else {
                        errorFrom(resp.code, text, resp.header("Retry-After"))
                    }
                }
            } catch (e: IOException) {
                ApiResult.Err("网络连接失败，请检查网络后重试。", code = -1)
            } catch (e: CancellationException) {
                throw e  // 结构化取消必须穿透，不得吞成业务错误
            } catch (e: Exception) {
                ApiResult.Err("请求出了问题：${e.message ?: "未知错误"}", code = -2)
            }
        }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (cont.isActive) cont.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (cont.isActive) cont.resume(response)
            }
        })
        cont.invokeOnCancellation { runCatching { cancel() } }
    }

    /** 契约 §2.3：detail 为字符串或 [{msg}] 数组；429 附 Retry-After 秒数提示。SSE 层 HTTP 失败也复用此解析。 */
    internal fun errorFrom(code: Int, body: String, retryAfter: String?): ApiResult.Err {
        val detail: String? = runCatching {
            val obj = Api.json.parseToJsonElement(body).jsonObject
            when (val d = obj["detail"]) {
                is JsonPrimitive -> d.content
                is JsonArray -> d.mapNotNull { el ->
                    (el as? JsonObject)?.get("msg")?.jsonPrimitive?.content
                }.joinToString("；")
                is JsonObject -> d.toString()
                else -> null
            }
        }.getOrNull()
        val ra = retryAfter?.trim()?.toIntOrNull()
        val suffix = if (code == 429 && ra != null && ra > 0) "（${ra}秒后再试）" else ""
        return ApiResult.Err((detail?.takeIf { it.isNotBlank() } ?: "请求失败（HTTP $code）") + suffix, code, ra)
    }
}
