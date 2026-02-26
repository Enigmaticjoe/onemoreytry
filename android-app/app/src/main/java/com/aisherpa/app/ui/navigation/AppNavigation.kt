package com.aisherpa.app.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.aisherpa.app.ui.screens.ChatScreen
import com.aisherpa.app.ui.screens.DashboardScreen
import com.aisherpa.app.ui.screens.KvmScreen
import com.aisherpa.app.ui.screens.SettingsScreen
import com.aisherpa.app.ui.theme.SherpaAccent
import com.aisherpa.app.ui.theme.SherpaBackground
import com.aisherpa.app.ui.theme.SherpaSurface
import com.aisherpa.app.ui.theme.TextPrimary
import com.aisherpa.app.ui.theme.TextSecondary
import com.aisherpa.app.viewmodel.ChatViewModel
import com.aisherpa.app.viewmodel.DashboardViewModel
import com.aisherpa.app.viewmodel.KvmViewModel

sealed class Screen(val route: String, val label: String, val icon: ImageVector) {
    data object Dashboard : Screen("dashboard", "Dashboard", Icons.Default.Dashboard)
    data object Chat : Screen("chat", "Sherpa", Icons.Default.Chat)
    data object Kvm : Screen("kvm", "KVM", Icons.Default.Keyboard)
    data object Settings : Screen("settings", "Settings", Icons.Default.Settings)
}

private val bottomNavItems = listOf(
    Screen.Dashboard,
    Screen.Chat,
    Screen.Kvm,
    Screen.Settings
)

@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val dashboardViewModel: DashboardViewModel = viewModel()
    val chatViewModel: ChatViewModel = viewModel()
    val kvmViewModel: KvmViewModel = viewModel()

    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = SherpaSurface) {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination

                bottomNavItems.forEach { screen ->
                    val selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true
                    NavigationBarItem(
                        icon = {
                            Icon(
                                imageVector = screen.icon,
                                contentDescription = screen.label
                            )
                        },
                        label = {
                            Text(
                                text = screen.label,
                                color = if (selected) SherpaAccent else TextSecondary
                            )
                        },
                        selected = selected,
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = SherpaAccent,
                            unselectedIconColor = TextSecondary,
                            indicatorColor = SherpaSurface
                        )
                    )
                }
            }
        },
        containerColor = SherpaBackground
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Dashboard.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Dashboard.route) {
                DashboardScreen(viewModel = dashboardViewModel)
            }
            composable(Screen.Chat.route) {
                ChatScreen(viewModel = chatViewModel)
            }
            composable(Screen.Kvm.route) {
                KvmScreen(viewModel = kvmViewModel)
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    onSave = { ccUrl, kvmUrl, kvmToken ->
                        chatViewModel.updateBaseUrl(ccUrl)
                        kvmViewModel.updateConfig(kvmUrl, kvmToken)
                    }
                )
            }
        }
    }
}
