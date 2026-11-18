package com.trainwithvimal.app

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The app's Dart side outlives the screen (Probid 18 Nov): when the app is swiped away from recent apps while a
 * workout runs, the workout service keeps the process alive, and with this kept engine the workout clock keeps
 * ticking and the workout notification comes back after a swipe in the shade, the same as with the app open.
 * Opening the app again shows the same running app at once. Without a workout Android ends the process as usual.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put(ENGINE, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    companion object {
        private const val ENGINE = "twv_main"
    }
}
