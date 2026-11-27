package com.yara.yara_academy

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // High-importance channel so push notifications pop down as a heads-up banner.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("yara_high", "إشعارات أكاديمية يارا", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "الرسائل والاشتراكات وتذكير الحصص"
            ch.enableVibration(true)
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(ch)

            val lesson = NotificationChannel("yara_lesson", "تنبيهات موعد الحصة", NotificationManager.IMPORTANCE_HIGH)
            lesson.description = "رنين تذكير دخول الحصة"
            lesson.enableVibration(true)
            val sound = Uri.parse("android.resource://$packageName/raw/${resources.getResourceEntryName(R.raw.yara_lesson)}")
            val audio = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            lesson.setSound(sound, audio)
            manager.createNotificationChannel(lesson)
        }
    }
}
