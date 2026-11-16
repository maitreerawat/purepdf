package com.maitreerawat.purepdf

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import com.maitreerawat.purepdf.ui.PurePdfAppScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val colorScheme = lightColorScheme(
            primary = Color(0xFF0F766E),
            secondary = Color(0xFFEA580C),
            tertiary = Color(0xFF4338CA)
        )
        setContent {
            MaterialTheme(colorScheme = colorScheme) {
                Surface {
                    PurePdfAppScreen()
                }
            }
        }
    }
}
