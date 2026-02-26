package com.aisherpa.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val SherpaColorScheme = darkColorScheme(
    primary = SherpaPrimary,
    onPrimary = TextOnPrimary,
    primaryContainer = SherpaPrimaryLight,
    onPrimaryContainer = TextOnPrimary,
    secondary = SherpaAccent,
    onSecondary = TextOnAccent,
    secondaryContainer = SherpaAccentLight,
    onSecondaryContainer = TextOnAccent,
    tertiary = NodeOnline,
    background = SherpaBackground,
    onBackground = TextPrimary,
    surface = SherpaSurface,
    onSurface = TextPrimary,
    surfaceVariant = SherpaSurfaceVariant,
    onSurfaceVariant = TextSecondary,
    error = NodeOffline,
    onError = TextOnPrimary,
    outline = TextSecondary,
)

@Composable
fun AISherpaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = SherpaColorScheme,
        typography = SherpaTypography,
        content = content
    )
}
