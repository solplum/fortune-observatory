package com.solplum.destiny.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily

/**
 * 默认主题：nailong 奶龙（design-spec §3.3 推荐默认，Web 端 initialTheme() 同款）。
 * v1 不做深色模式适配（范围外），恒用浅色方案。
 */
object DestinyColors {
    val Ink = Color(0xFF101010)
    val Paper = Color(0xFFFFFEF6)
    val Surface = Color(0xFFFFFFFF)
    val Accent = Color(0xFF0758F7)
    val Accent2 = Color(0xFFFF3044)
    val Wash = Color(0xFFFFE81A)
    val Muted = Color(0xFF5C5A4F)
    val Line = Color(0xFF111111)
    val SoftLine = Color(0x24111111)   // rgba(17,17,17,.14)
    val WarnBg = Color(0xFFFFF3CD)     // 「注意」节琥珀色提示块（design-spec §4.2）
    val GoodBg = Color(0xFFE7F6E9)
}

val ReadingFont: FontFamily = FontFamily.Serif

private val DestinyScheme = lightColorScheme(
    primary = DestinyColors.Accent,
    onPrimary = Color.White,
    secondary = DestinyColors.Accent2,
    onSecondary = Color.White,
    tertiary = Color(0xFF8A7500),
    tertiaryContainer = DestinyColors.Wash,
    onTertiaryContainer = DestinyColors.Ink,
    background = DestinyColors.Paper,
    onBackground = DestinyColors.Ink,
    surface = DestinyColors.Surface,
    onSurface = DestinyColors.Ink,
    surfaceVariant = Color(0xFFF3F1E8),
    onSurfaceVariant = DestinyColors.Muted,
    outline = DestinyColors.Line,
    outlineVariant = DestinyColors.SoftLine,
    error = Color(0xFFC62828),
)

@Composable
fun DestinyTheme(content: @Composable () -> Unit) {
    @Suppress("UNUSED_EXPRESSION")
    isSystemInDarkTheme() // v1 不适配深色，仅为引用完整性
    MaterialTheme(
        colorScheme = DestinyScheme,
        content = content,
    )
}
