package com.aisherpa.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.aisherpa.app.ui.navigation.AppNavigation
import com.aisherpa.app.ui.theme.AISherpaTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AISherpaTheme {
                AppNavigation()
            }
        }
    }
}
