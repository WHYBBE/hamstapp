package com.hamstapp.hamstapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "hamstapp/apps"
    private var plugin: PackageScannerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        plugin = PackageScannerPlugin(applicationContext, channel)
        channel.setMethodCallHandler(plugin)
    }

    override fun onDestroy() {
        plugin = null
        super.onDestroy()
    }
}
