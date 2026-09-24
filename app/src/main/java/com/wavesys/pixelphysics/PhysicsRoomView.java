package com.wavesys.pixelphysics;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Locale;

/**
 * A deliberately 2D renderer with a 2.5D projection layer.
 *
 * There is no 3D engine here. Bodies live on a flat (u,v) floor plane plus one
 * scalar height z. The screen projection is isometric-like and all rendering is
 * Canvas raster/vector work. This keeps the visual language locked to pixel art.
 */
public final class PhysicsRoomView extends View {
    private static final float DESIGN = 256f;
    private static final float ISO_X = 92f;
    private static final float ISO_Y = 62f;
    private static final float ISO_Z = 74f;
    private static final float ORIGIN_X = 128f;
    private static final float ORIGIN_Y = 87f;

    private static final float GRAVITY_Z = -2.35f;
    private static final float FLOOR_RESTITUTION = 0.36f;
    private static final float WALL_RESTITUTION = 0.63f;
    private static final float DRAG_FRICTION = 0.987f;

    private final Paint paint = new Paint();
    private final Paint bitmapPaint = new Paint();
    private final ArrayList<Body> bodies = new ArrayList<>();
    private final RectF sceneRect = new RectF();
    private final Bitmap roomBitmap;
    private Throwable fatalError = null;

    private long lastFrameNs = 0L;
    private Body held = null;
    private Body selected = null;
    private float downDesignX;
    private float downDesignY;
    private float lastDesignX;
    private float lastDesignY;
    private long downMs;
    private long lastMoveMs;
    private long lastTapMs;
    private float lastTapX;
    private float lastTapY;
    private float pendingVu;
    private float pendingVv;

    public PhysicsRoomView(Context context) {
        super(context);
        setKeepScreenOn(true);
        setLayerType(View.LAYER_TYPE_SOFTWARE, null);

        bitmapPaint.setAntiAlias(false);
        bitmapPaint.setFilterBitmap(false);
        paint.setAntiAlias(false);
        paint.setDither(false);
        roomBitmap = BitmapFactory.decodeResource(
                getResources(),
                R.drawable.reference_room
        );

        seedScene();
    }

    private void seedScene() {
        bodies.clear();
        bodies.add(Body.cube(0.31f, 0.72f, 0.050f, 0xFF2A75B9));
        bodies.add(Body.cube(0.73f, 0.69f, 0.050f, 0xFFE0442F));
        bodies.add(Body.ball(0.43f, 0.34f, 0.050f));
        bodies.add(Body.plank(0.58f, 0.78f, 0.095f, -0.28f));
        bodies.add(Body.cube(0.70f, 0.49f, 0.050f, 0xFF4EA54E));
        bodies.add(Body.cube(0.72f, 0.53f, 0.050f, 0xFF2C78BA));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (fatalError != null) {
            drawFatal(canvas, fatalError);
            return;
        }

        try {
            renderFrame(canvas);
        } catch (Throwable renderError) {
            fatalError = renderError;
            drawFatal(canvas, renderError);
        }
    }

    private void renderFrame(Canvas canvas) {
        computeSceneRect();

        canvas.drawColor(Color.rgb(15, 20, 29));
        if (roomBitmap != null) {
            canvas.drawBitmap(roomBitmap, null, sceneRect, bitmapPaint);
        }

        final long now = System.nanoTime();
        if (lastFrameNs == 0L) lastFrameNs = now;
        float dt = (now - lastFrameNs) * 1e-9f;
        lastFrameNs = now;
        dt = clamp(dt, 0f, 1f / 24f);

        if (held == null) {
            stepPhysics(dt);
        } else {
            stepPhysicsExceptHeld(dt);
        }

        canvas.save();
        canvas.translate(sceneRect.left, sceneRect.top);
        float scale = sceneRect.width() / DESIGN;
        canvas.scale(scale, scale);
        drawWorld(canvas);
        canvas.restore();

        postInvalidateOnAnimation();
    }

    private void drawFatal(Canvas canvas, Throwable error) {
        canvas.drawColor(Color.rgb(15, 20, 29));
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.WHITE);
        paint.setTextAlign(Paint.Align.LEFT);
        paint.setTypeface(android.graphics.Typeface.MONOSPACE);
        paint.setTextSize(18f);
        canvas.drawText("PIXEL PHYSICS - RENDER ERROR", 28f, 60f, paint);
        paint.setTextSize(13f);
        canvas.drawText(error.getClass().getSimpleName(), 28f, 90f, paint);
        String message = String.valueOf(error.getMessage());
        if (message.length() > 80) message = message.substring(0, 80);
        canvas.drawText(message, 28f, 115f, paint);
    }

    private void computeSceneRect() {
        float s = Math.min(getWidth(), getHeight());
        float left = (getWidth() - s) * 0.5f;
        float top = (getHeight() - s) * 0.5f;
        sceneRect.set(left, top, left + s, top + s);
    }

    private void stepPhysics(float dt) {
        for (Body b : bodies) stepBody(b, dt);
        solvePairCollisions();
    }

    private void stepPhysicsExceptHeld(float dt) {
        for (Body b : bodies) {
            if (b != held) stepBody(b, dt);
        }
        solvePairCollisions();
    }

    private void stepBody(Body b, float dt) {
        b.u += b.vu * dt;
        b.v += b.vv * dt;
        b.z += b.vz * dt;
        b.vz += GRAVITY_Z * dt;
        b.angle += b.angularVelocity * dt;

        float r = b.radius;
        if (b.u < r) {
            b.u = r;
            b.vu = Math.abs(b.vu) * WALL_RESTITUTION;
        } else if (b.u > 1f - r) {
            b.u = 1f - r;
            b.vu = -Math.abs(b.vu) * WALL_RESTITUTION;
        }

        if (b.v < r) {
            b.v = r;
            b.vv = Math.abs(b.vv) * WALL_RESTITUTION;
        } else if (b.v > 1f - r) {
            b.v = 1f - r;
            b.vv = -Math.abs(b.vv) * WALL_RESTITUTION;
        }

        if (b.z <= 0f) {
            b.z = 0f;
            if (b.vz < -0.08f) b.vz = -b.vz * FLOOR_RESTITUTION;
            else b.vz = 0f;
            b.vu *= DRAG_FRICTION;
            b.vv *= DRAG_FRICTION;
            b.angularVelocity *= 0.985f;
        }
    }

    private void solvePairCollisions() {
        for (int i = 0; i < bodies.size(); i++) {
            Body a = bodies.get(i);
            for (int j = i + 1; j < bodies.size(); j++) {
                Body b = bodies.get(j);
                if (Math.abs(a.z - b.z) > 0.11f) continue;

                float du = b.u - a.u;
                float dv = b.v - a.v;
                float minD = a.radius + b.radius;
                float d2 = du * du + dv * dv;
                if (d2 <= 0.0000001f || d2 >= minD * minD) continue;

                float d = (float) Math.sqrt(d2);
                float nx = du / d;
                float ny = dv / d;
                float penetration = minD - d;

                if (a != held && b != held) {
                    a.u -= nx * penetration * 0.5f;
                    a.v -= ny * penetration * 0.5f;
                    b.u += nx * penetration * 0.5f;
                    b.v += ny * penetration * 0.5f;
                } else if (a == held && b != held) {
                    b.u += nx * penetration;
                    b.v += ny * penetration;
                } else if (b == held && a != held) {
                    a.u -= nx * penetration;
                    a.v -= ny * penetration;
                }

                float rvx = b.vu - a.vu;
                float rvy = b.vv - a.vv;
                float vn = rvx * nx + rvy * ny;
                if (vn < 0f) {
                    float impulse = -(1f + 0.66f) * vn * 0.5f;
                    if (a != held) {
                        a.vu -= impulse * nx;
                        a.vv -= impulse * ny;
                    }
                    if (b != held) {
                        b.vu += impulse * nx;
                        b.vv += impulse * ny;
                    }
                }
            }
        }
    }

    private void drawWorld(Canvas c) {
        ArrayList<Body> ordered = new ArrayList<>(bodies);
        Collections.sort(ordered, Comparator.comparingDouble(b -> b.u + b.v));

        for (Body b : ordered) {
            drawShadow(c, b);
        }
        for (Body b : ordered) {
            if (b.type == Body.Type.BALL) drawBall(c, b);
            else if (b.type == Body.Type.CUBE) drawCube(c, b);
            else drawPlank(c, b);
        }

        if (selected != null) drawSelection(c, selected);
        drawHint(c);
    }

    private void drawShadow(Canvas c, Body b) {
        Point p = project(b.u, b.v, 0f);
        float depth = depthScale(b);
        float rx = b.type == Body.Type.PLANK ? 18f * depth : 7.5f * depth;
        float ry = b.type == Body.Type.PLANK ? 4.5f * depth : 3.8f * depth;
        float alpha = clamp(0.48f - b.z * 0.60f, 0.08f, 0.48f);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.argb((int) (255 * alpha), 32, 25, 23));
        c.drawOval(new RectF(p.x - rx, p.y - ry, p.x + rx, p.y + ry), paint);
    }

    private void drawCube(Canvas c, Body b) {
        Point p = project(b.u, b.v, b.z);
        float s = 10.0f * depthScale(b);
        float h = s * 1.05f;
        int top = lighten(b.color, 1.22f);
        int left = darken(b.color, 0.72f);
        int right = darken(b.color, 0.86f);
        int outline = Color.rgb(33, 31, 34);

        Path topFace = new Path();
        topFace.moveTo(p.x, p.y - h);
        topFace.lineTo(p.x + s, p.y - h * 0.52f);
        topFace.lineTo(p.x, p.y);
        topFace.lineTo(p.x - s, p.y - h * 0.52f);
        topFace.close();

        Path leftFace = new Path();
        leftFace.moveTo(p.x - s, p.y - h * 0.52f);
        leftFace.lineTo(p.x, p.y);
        leftFace.lineTo(p.x, p.y + h);
        leftFace.lineTo(p.x - s, p.y + h * 0.48f);
        leftFace.close();

        Path rightFace = new Path();
        rightFace.moveTo(p.x + s, p.y - h * 0.52f);
        rightFace.lineTo(p.x, p.y);
        rightFace.lineTo(p.x, p.y + h);
        rightFace.lineTo(p.x + s, p.y + h * 0.48f);
        rightFace.close();

        paint.setStyle(Paint.Style.FILL);
        paint.setColor(left); c.drawPath(leftFace, paint);
        paint.setColor(right); c.drawPath(rightFace, paint);
        paint.setColor(top); c.drawPath(topFace, paint);

        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1.35f);
        paint.setColor(outline);
        c.drawPath(topFace, paint);
        c.drawPath(leftFace, paint);
        c.drawPath(rightFace, paint);

        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.argb(105, 255, 255, 255));
        c.drawRect(p.x - s * 0.52f, p.y - h * 0.74f, p.x - s * 0.18f, p.y - h * 0.57f, paint);
    }

    private void drawBall(Canvas c, Body b) {
        Point p = project(b.u, b.v, b.z);
        float r = 8.5f * depthScale(b);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.rgb(229, 229, 222));
        c.drawCircle(p.x, p.y, r, paint);
        paint.setColor(Color.rgb(179, 181, 188));
        c.drawCircle(p.x + r * 0.18f, p.y + r * 0.22f, r * 0.73f, paint);
        paint.setColor(Color.rgb(247, 246, 233));
        c.drawCircle(p.x - r * 0.28f, p.y - r * 0.33f, r * 0.45f, paint);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1.35f);
        paint.setColor(Color.rgb(42, 40, 45));
        c.drawCircle(p.x, p.y, r, paint);
    }

    private void drawPlank(Canvas c, Body b) {
        Point p = project(b.u, b.v, b.z);
        float scale = depthScale(b);
        float len = 27f * scale;
        float halfW = 3.6f * scale;
        float ca = (float) Math.cos(b.angle);
        float sa = (float) Math.sin(b.angle);

        float x1 = p.x - len * ca;
        float y1 = p.y - len * sa;
        float x2 = p.x + len * ca;
        float y2 = p.y + len * sa;
        float nx = -sa * halfW;
        float ny = ca * halfW;

        Path face = new Path();
        face.moveTo(x1 + nx, y1 + ny);
        face.lineTo(x2 + nx, y2 + ny);
        face.lineTo(x2 - nx, y2 - ny);
        face.lineTo(x1 - nx, y1 - ny);
        face.close();

        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.rgb(194, 113, 48));
        c.drawPath(face, paint);
        paint.setColor(Color.rgb(226, 146, 66));
        paint.setStrokeWidth(1.7f);
        paint.setStyle(Paint.Style.STROKE);
        c.drawLine(x1 + nx * 0.55f, y1 + ny * 0.55f, x2 + nx * 0.55f, y2 + ny * 0.55f, paint);
        paint.setColor(Color.rgb(54, 34, 28));
        paint.setStrokeWidth(1.4f);
        c.drawPath(face, paint);
    }

    private void drawSelection(Canvas c, Body b) {
        Point p = project(b.u, b.v, b.z);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1.2f);
        paint.setColor(Color.argb(170, 255, 226, 146));
        float r = (b.type == Body.Type.PLANK ? 31f : 13f) * depthScale(b);
        c.drawCircle(p.x, p.y, r, paint);
    }

    private void drawHint(Canvas c) {
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.argb(125, 10, 14, 20));
        c.drawRoundRect(new RectF(55f, 232f, 201f, 250f), 3f, 3f, paint);
        paint.setColor(Color.argb(210, 244, 226, 183));
        paint.setTextSize(5.4f);
        paint.setTypeface(android.graphics.Typeface.MONOSPACE);
        paint.setTextAlign(Paint.Align.CENTER);
        c.drawText("DRAG = THROW   TAP = CUBE   HOLD = BALL   DOUBLE = JUMP", 128f, 243.4f, paint);
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        if (fatalError != null) return true;
        try {
            return handleTouchEvent(e);
        } catch (Throwable touchError) {
            fatalError = touchError;
            invalidate();
            return true;
        }
    }

    private boolean handleTouchEvent(MotionEvent e) {
        if (sceneRect.width() <= 0f) return true;
        float dx = (e.getX() - sceneRect.left) * DESIGN / sceneRect.width();
        float dy = (e.getY() - sceneRect.top) * DESIGN / sceneRect.height();
        long nowMs = SystemClock.uptimeMillis();

        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downDesignX = lastDesignX = dx;
                downDesignY = lastDesignY = dy;
                downMs = lastMoveMs = nowMs;
                pendingVu = pendingVv = 0f;
                held = hitTest(dx, dy);
                selected = held;
                if (held != null) {
                    held.vu = held.vv = 0f;
                    held.angularVelocity = 0f;
                }
                return true;

            case MotionEvent.ACTION_MOVE:
                if (held != null) {
                    long dtMs = Math.max(1L, nowMs - lastMoveMs);
                    float[] uv = inverseProject(dx, dy, held.z);
                    float oldU = held.u;
                    float oldV = held.v;
                    held.u = clamp(uv[0], held.radius, 1f - held.radius);
                    held.v = clamp(uv[1], held.radius, 1f - held.radius);
                    float sec = dtMs / 1000f;
                    pendingVu = clamp((held.u - oldU) / sec, -2.8f, 2.8f);
                    pendingVv = clamp((held.v - oldV) / sec, -2.8f, 2.8f);
                    held.angle += (dx - lastDesignX) * 0.012f;
                }
                lastDesignX = dx;
                lastDesignY = dy;
                lastMoveMs = nowMs;
                return true;

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                float moved = dist(dx, dy, downDesignX, downDesignY);
                if (held != null) {
                    Body released = held;
                    held = null;
                    if (e.getActionMasked() == MotionEvent.ACTION_UP) {
                        released.vu = pendingVu * 0.55f;
                        released.vv = pendingVv * 0.55f;
                        released.angularVelocity = clamp((dx - downDesignX) * 0.03f, -4f, 4f);

                        boolean doubleTap = (nowMs - lastTapMs) < 320L
                                && dist(dx, dy, lastTapX, lastTapY) < 18f;
                        if (doubleTap && moved < 10f) {
                            released.vz = 1.12f;
                        }
                    }
                } else if (e.getActionMasked() == MotionEvent.ACTION_UP && moved < 10f) {
                    float[] uv = inverseProject(dx, dy, 0f);
                    if (uv[0] >= 0f && uv[0] <= 1f && uv[1] >= 0f && uv[1] <= 1f) {
                        if ((nowMs - downMs) > 470L) {
                            Body b = Body.ball(uv[0], uv[1], 0.050f);
                            b.vz = 0.68f;
                            bodies.add(b);
                            selected = b;
                        } else {
                            int[] palette = {0xFFE0442F, 0xFF2A75B9, 0xFF50A45A, 0xFFD38E35};
                            int color = palette[bodies.size() % palette.length];
                            Body b = Body.cube(uv[0], uv[1], 0.050f, color);
                            b.vz = 0.46f;
                            bodies.add(b);
                            selected = b;
                        }
                    }
                }

                lastTapMs = nowMs;
                lastTapX = dx;
                lastTapY = dy;
                return true;
        }
        return true;
    }

    private Body hitTest(float sx, float sy) {
        Body best = null;
        float bestD = Float.MAX_VALUE;
        for (Body b : bodies) {
            Point p = project(b.u, b.v, b.z);
            float d = dist(sx, sy, p.x, p.y);
            float threshold = b.type == Body.Type.PLANK ? 30f : 15f;
            if (d < threshold && d < bestD) {
                best = b;
                bestD = d;
            }
        }
        return best;
    }

    private Point project(float u, float v, float z) {
        float x = ORIGIN_X + (u - v) * ISO_X;
        float y = ORIGIN_Y + (u + v) * ISO_Y - z * ISO_Z;
        return new Point(x, y);
    }

    private float[] inverseProject(float x, float y, float z) {
        float a = (x - ORIGIN_X) / ISO_X;
        float b = (y + z * ISO_Z - ORIGIN_Y) / ISO_Y;
        float u = (a + b) * 0.5f;
        float v = (b - a) * 0.5f;
        return new float[]{u, v};
    }

    private float depthScale(Body b) {
        return 0.78f + 0.30f * clamp((b.u + b.v) * 0.5f, 0f, 1f);
    }

    private static float dist(float ax, float ay, float bx, float by) {
        float dx = ax - bx;
        float dy = ay - by;
        return (float) Math.sqrt(dx * dx + dy * dy);
    }

    private static float clamp(float v, float min, float max) {
        return Math.max(min, Math.min(max, v));
    }

    private static int lighten(int color, float factor) {
        return Color.rgb(
                (int) clamp(Color.red(color) * factor, 0, 255),
                (int) clamp(Color.green(color) * factor, 0, 255),
                (int) clamp(Color.blue(color) * factor, 0, 255)
        );
    }

    private static int darken(int color, float factor) {
        return Color.rgb(
                (int) clamp(Color.red(color) * factor, 0, 255),
                (int) clamp(Color.green(color) * factor, 0, 255),
                (int) clamp(Color.blue(color) * factor, 0, 255)
        );
    }

    private static final class Point {
        final float x;
        final float y;
        Point(float x, float y) { this.x = x; this.y = y; }
    }

    private static final class Body {
        enum Type { CUBE, BALL, PLANK }

        Type type;
        float u;
        float v;
        float z;
        float vu;
        float vv;
        float vz;
        float radius;
        float angle;
        float angularVelocity;
        int color;

        static Body cube(float u, float v, float r, int color) {
            Body b = new Body();
            b.type = Type.CUBE;
            b.u = u; b.v = v; b.radius = r; b.color = color;
            return b;
        }

        static Body ball(float u, float v, float r) {
            Body b = new Body();
            b.type = Type.BALL;
            b.u = u; b.v = v; b.radius = r; b.color = 0xFFE7E5DB;
            return b;
        }

        static Body plank(float u, float v, float r, float angle) {
            Body b = new Body();
            b.type = Type.PLANK;
            b.u = u; b.v = v; b.radius = r; b.angle = angle; b.color = 0xFFC77936;
            return b;
        }

        @Override
        public String toString() {
            return String.format(Locale.US, "%s(%.2f,%.2f,%.2f)", type, u, v, z);
        }
    }
}
