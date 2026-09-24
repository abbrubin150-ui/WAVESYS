package com.wavesys.pixelphysics;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.TextView;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN
        );

        try {
            setContentView(new PhysicsRoomView(this));
        } catch (Throwable startupError) {
            TextView fallback = new TextView(this);
            fallback.setBackgroundColor(Color.rgb(15, 20, 29));
            fallback.setTextColor(Color.WHITE);
            fallback.setTextSize(16f);
            fallback.setGravity(Gravity.CENTER);
            fallback.setPadding(48, 48, 48, 48);
            fallback.setText(
                    "Pixel Physics Sandbox\n\n"
                    + "Renderer startup failed instead of closing the app.\n\n"
                    + startupError.getClass().getSimpleName()
                    + ": "
                    + String.valueOf(startupError.getMessage())
            );
            setContentView(fallback);
        }
    }
}
