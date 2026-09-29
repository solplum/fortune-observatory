package com.solplum.destiny.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.solplum.destiny.ui.screens.AskScreen
import com.solplum.destiny.ui.screens.ChartScreen
import com.solplum.destiny.ui.screens.DreamScreen
import com.solplum.destiny.ui.screens.FortuneScreen
import com.solplum.destiny.ui.screens.HomeScreen
import com.solplum.destiny.ui.screens.QimenScreen
import com.solplum.destiny.ui.screens.TcmScreen

object Routes {
    const val HOME = "home"
    const val CHART = "chart"
    const val FORTUNE = "fortune"
    const val ASK = "ask"
    const val DREAM = "dream"
    const val QIMEN = "qimen"
    const val TCM = "tcm"

    fun titleOf(route: String): String = when (route) {
        CHART -> "排盘"
        FORTUNE -> "运势"
        ASK -> "问事"
        DREAM -> "解梦"
        QIMEN -> "奇门遁甲"
        TCM -> "中医问诊"
        else -> "看运"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot() {
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route ?: Routes.HOME
    val isHome = route == Routes.HOME

    DestinyTheme {
        Scaffold(
            containerColor = DestinyColors.Paper,
            topBar = {
                TopAppBar(
                    title = { Text(Routes.titleOf(route), fontWeight = FontWeight.Bold) },
                    navigationIcon = {
                        if (!isHome) {
                            IconButton(onClick = { nav.popBackStack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = DestinyColors.Paper,
                        titleContentColor = DestinyColors.Ink,
                    ),
                )
            },
        ) { pad ->
            NavHost(nav, startDestination = Routes.HOME, modifier = Modifier.padding(pad)) {
                composable(Routes.HOME) { HomeScreen(nav) }
                composable(Routes.CHART) { ChartScreen(nav) }
                composable(Routes.FORTUNE) { FortuneScreen(nav) }
                composable(Routes.ASK) { AskScreen(nav) }
                composable(Routes.DREAM) { DreamScreen(nav) }
                composable(Routes.QIMEN) { QimenScreen(nav) }
                composable(Routes.TCM) { TcmScreen(nav) }
            }
        }
    }
}
