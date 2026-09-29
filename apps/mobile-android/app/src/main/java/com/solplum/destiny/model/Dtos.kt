package com.solplum.destiny.model

import kotlinx.serialization.Serializable

// ============ 请求体（服务端 extra="forbid"，字段名与数量必须逐字对齐契约）============

@Serializable
data class BirthRequest(
    val civil_datetime: String,
    val timezone_id: String,
    val longitude: Double,
    val latitude: Double,
    val sex_for_rule: String,
    val use_apparent_solar_time: Boolean,
)

@Serializable
data class DailyTransitRequest(val birth: BirthRequest, val transit_date: String)

@Serializable
data class TransitWindowRequest(val birth: BirthRequest, val start_date: String, val end_date: String)

@Serializable
data class ReadingHistoryItem(val role: String, val text: String)

@Serializable
data class ReadingRequest(
    val question: String,
    val split_questions: List<String>,
    val context_tokens: List<String>,
    val history: List<ReadingHistoryItem>,
    val stream_key: String,
)

@Serializable
data class DreamRequest(val dream: String)

@Serializable
data class TcmRequest(val question: String)

@Serializable
data class QimenChartRequest(
    val question_type: String,
    val question_goal: String,
    val time_mode: String,
    val time_input: String? = null,
    val city: String,
    val detail_level: String,
)

// ============ /v1/charts 响应（契约 §3.1；全部字段带默认值做宽容解析）============

@Serializable
data class ChartResponse(
    val bazi: BaziInfo = BaziInfo(),
    val ziwei: ZiweiInfo = ZiweiInfo(),
    val qizheng: QizhengInfo = QizhengInfo(),
    val time_trace: TimeTrace? = null,
    val natal_insights: List<Insight> = emptyList(),
    val trace_id: String = "",
    val ai_contexts: Map<String, ContextBundle> = emptyMap(),
)

@Serializable
data class BaziInfo(
    val calculation_datetime: String = "",
    val input_time_basis: String = "",
    val pillars: Pillars = Pillars(),
    val pillar_details: List<PillarDetail> = emptyList(),
    val lunar_date: String = "",
    val great_luck_start: GreatLuckStart? = null,
    val great_luck_periods: List<GreatLuckPeriod> = emptyList(),
    val warnings: List<String> = emptyList(),
    val verification_status: String = "",
)

@Serializable
data class Pillars(
    val year: String = "",
    val month: String = "",
    val day: String = "",
    val hour: String = "",
)

@Serializable
data class PillarDetail(
    val pillar: String = "",
    val ten_god: String? = null,
    val hidden_stems: List<HiddenStem> = emptyList(),
    val nayin: String? = null,
)

@Serializable
data class HiddenStem(val stem: String = "", val ten_god: String? = null)

@Serializable
data class GreatLuckStart(
    val years: Int = 0,
    val months: Int = 0,
    val days: Int = 0,
    val direction: String = "",
    val first_pillar: String = "",
)

@Serializable
data class GreatLuckPeriod(
    val pillar: String = "",
    val start_datetime: String = "",
    val end_datetime: String = "",
    val start_age: Int = 0,
    val end_age: Int = 0,
)

@Serializable
data class ZiweiInfo(
    val lunar_month: Int = 0,
    val hour_branch: String = "",
    val life_branch: String = "",
    val body_branch: String = "",
    val five_elements_bureau: Int = 0,
    val year_stem: String = "",
    val birth_mutagens: List<Mutagen> = emptyList(),
    val palaces: List<Palace> = emptyList(),
    val flying_mutagens: List<FlyingMutagen> = emptyList(),
    val verification_status: String = "",
)

@Serializable
data class Mutagen(val star: String = "", val mutagen: String = "")

@Serializable
data class Palace(
    val name: String = "",
    val stem: String = "",
    val branch: String = "",
    val is_body_palace: Boolean = false,
    val decadal_range: List<Int> = emptyList(),
    val minor_limit_ages: List<Int> = emptyList(),
    val major_stars: List<String> = emptyList(),
    val major_star_brightness: List<List<String>> = emptyList(),
    val minor_stars: List<String> = emptyList(),
)

@Serializable
data class FlyingMutagen(
    val from_branch: String = "",
    val stem: String = "",
    val mutagen: String = "",
    val star: String = "",
    val to_branch: String = "",
    val is_self: Boolean = false,
)

@Serializable
data class QizhengInfo(
    val bodies: List<QizhengBody> = emptyList(),
    val traditional: QizhengTraditional? = null,
    val scope_limits: List<String> = emptyList(),
    val verification_status: String = "",
)

@Serializable
data class QizhengBody(
    val body: String = "",
    val longitude_deg: Double = 0.0,
    val latitude_deg: Double? = null,
    val motion: String = "",
)

@Serializable
data class QizhengTraditional(
    val bodies: List<QizhengTradBody> = emptyList(),
    val houses: QizhengHouses? = null,
    val life_lord: String = "",
    val body_lord: String = "",
    val is_day_chart: Boolean = true,
    val childhood_exit_age: Double = 0.0,
    val limit_rows: List<LimitRow> = emptyList(),
    val verification_status: String = "",
)

@Serializable
data class QizhengTradBody(
    val body: String = "",
    val longitude_deg: Double = 0.0,
    val motion: String = "",
    val mansion: String? = null,
    val mansion_branch: String? = null,
    val mansion_offset_deg: Double? = null,
    val dignity: String? = null,
    val relation: String? = null,
)

@Serializable
data class QizhengHouses(
    val life_branch: String = "",
    val body_branch: String = "",
    val houses: List<List<String>> = emptyList(),
)

@Serializable
data class LimitRow(
    val palace: String = "",
    val branch: String = "",
    val years: Double = 0.0,
    val start_age: Double = 0.0,
    val end_age: Double = 0.0,
    val segment: String = "",
)

@Serializable
data class TimeTrace(
    val timezone_id: String = "",
    val civil_datetime: String = "",
    val local_mean_solar_datetime: String = "",
    val apparent_solar_datetime: String = "",
    val apparent_solar_source: String = "",
)

@Serializable
data class Insight(
    val title: String = "",
    val summary: String = "",
    val action: String = "",
    val fact_ids: List<String> = emptyList(),
)

@Serializable
data class ContextBundle(val token: String = "", val facts: List<ContextFact> = emptyList())

@Serializable
data class ContextFact(val id: String = "", val text: String = "")

// ============ 运势响应（契约 §3.2 / §3.3）============

@Serializable
data class DailyTransitResponse(
    val transit: DailyTransit = DailyTransit(),
    val trace_id: String = "",
    val ziwei_yearly: ZiweiYearly? = null,
    val ai_context: ContextBundle? = null,
    val ai_context_bazi: ContextBundle? = null,
)

@Serializable
data class DailyTransit(
    val transit_date: String = "",
    val day_pillar: String = "",
    val facts: List<TransitFact> = emptyList(),
    val verification_status: String = "",
)

@Serializable
data class TransitFact(
    val fact_id: String = "",
    val relation: String = "",
    val natal_pillar: String = "",
    val transit_pillar: String = "",
)

@Serializable
data class ZiweiYearly(
    val year_pillar: String = "",
    val nominal_age: Int = 0,
    val life_branch: String = "",
    val yearly_mutagens: List<YearlyMutagen> = emptyList(),
    val flowing_stars: List<FlowingStar> = emptyList(),
    val decadal: DecadalInfo? = null,
)

@Serializable
data class YearlyMutagen(
    val star: String = "",
    val mutagen: String = "",
    val palace_branch: String = "",
    val palace_name: String = "",
)

@Serializable
data class FlowingStar(val star: String = "", val branch: String = "")

@Serializable
data class DecadalInfo(
    val branch: String = "",
    val stem: String = "",
    val start_age: Int = 0,
    val end_age: Int = 0,
    val is_childhood: Boolean = false,
)

@Serializable
data class WindowTransitResponse(
    val transit: WindowTransit = WindowTransit(),
    val trace_id: String = "",
    val ai_context: ContextBundle? = null,
    val ai_context_bazi: ContextBundle? = null,
)

@Serializable
data class WindowTransit(
    val start_date: String = "",
    val end_date: String = "",
    val daily: List<DailyTransit> = emptyList(),
    val verification_status: String = "",
)

// ============ /v1/transits 时间层事实（契约 §3.4；请求体同 daily）============

@Serializable
data class TransitResponse(
    val transit: TransitLayers = TransitLayers(),
    val trace_id: String = "",
    val ai_context: ContextBundle? = null,
)

@Serializable
data class TransitLayers(
    val layers: List<TransitLayer> = emptyList(),
    val ziwei_annual: ZiweiAnnual? = null,
    val signals: List<TransitSignal> = emptyList(),
    val insights: List<Insight> = emptyList(),
)

@Serializable
data class TransitLayer(
    val period: String = "",
    val pillar: String = "",
    val facts: List<TransitFact> = emptyList(),
)

@Serializable
data class ZiweiAnnual(val palaces: List<AnnualPalace> = emptyList())

@Serializable
data class AnnualPalace(val name: String = "", val branch: String = "")

@Serializable
data class TransitSignal(val direction: String = "")

// ============ 状态与健康（契约 §3.5 / §3.6）============

@Serializable
data class AiStatusResponse(
    val available: Boolean = false,
    val mode: String = "",
    val attaches_birth_profile: Boolean = false,
)

@Serializable
data class HealthResponse(val status: String = "", val engine: String = "")
