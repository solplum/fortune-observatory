package com.solplum.destiny.model

import androidx.compose.ui.graphics.Color

/** 天干地支五行映射与七政四余星曜中文名（design-spec §4.1 el-wood/fire/earth/metal/water 着色口径）。 */
object GanZhi {

    fun elementOf(char: Char): String = when (char) {
        '甲', '乙', '寅', '卯' -> "木"
        '丙', '丁', '巳', '午' -> "火"
        '戊', '己', '辰', '未', '戌' -> "土"
        '庚', '辛', '申', '酉' -> "金"
        '壬', '癸', '亥', '子' -> "水"
        else -> ""
    }

    fun elementColor(element: String): Color = when (element) {
        "木" -> Color(0xFF2E7D32)
        "火" -> Color(0xFFC62828)
        "土" -> Color(0xFF8D6E63)
        "金" -> Color(0xFF9A7B00)
        "水" -> Color(0xFF1565C0)
        else -> Color(0xFF5C5A4F)
    }

    fun colorOfChar(char: Char): Color = elementColor(elementOf(char))

    private val BRANCH_ORDER = "子丑寅卯辰巳午未申酉戌亥"

    fun branchIndex(branch: String): Int = BRANCH_ORDER.indexOf(branch.take(1)).let { if (it < 0) 99 else it }

    /** 七政四余星曜 body id -> 中文名（实测全集：sun..ziqi，2026-09-29 /v1/charts）。 */
    fun qizhengBodyName(body: String): String = when (body) {
        "sun" -> "太阳"
        "moon" -> "太阴"
        "mercury" -> "水星"
        "venus" -> "金星"
        "mars" -> "火星"
        "jupiter" -> "木星"
        "saturn" -> "土星"
        "rahu" -> "罗睺"
        "ketu" -> "计都"
        "apogee" -> "月孛"
        "ziqi" -> "紫气"
        else -> body
    }

    fun lordName(lord: String): String = when (lord) {
        "sun" -> "太阳"; "moon" -> "太阴"; "mercury" -> "水星"; "venus" -> "金星"
        "mars" -> "火星"; "jupiter" -> "木星"; "saturn" -> "土星"
        else -> lord
    }

    fun motionText(motion: String): String = when (motion) {
        "direct" -> "顺行"; "retrograde" -> "逆行"; "stationary" -> "留"
        else -> motion
    }

    /** 地支相冲/合/同支的中文口径（contract §3.2 relation 枚举）。 */
    fun relationText(relation: String): String = when (relation) {
        "branch_clash" -> "地支相冲"
        "branch_combination" -> "地支相合"
        "branch_same" -> "地支同支"
        else -> relation
    }

    /** 四柱八字里出现的五行计数。 */
    fun fiveElementCounts(pillars: List<String>): Map<String, Int> {
        val counts = linkedMapOf("木" to 0, "火" to 0, "土" to 0, "金" to 0, "水" to 0)
        pillars.flatMap { it.toCharArray().toList() }.forEach { c ->
            val el = elementOf(c)
            if (el.isNotEmpty()) counts[el] = (counts[el] ?: 0) + 1
        }
        return counts
    }
}
