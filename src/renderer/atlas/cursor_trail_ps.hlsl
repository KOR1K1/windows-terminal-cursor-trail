// Built-in effect for the "cursorTrail" profile setting.
// When the cursor jumps, it stretches toward the new position and the tail
// catches up a moment later, with motion blur.
// samples/PixelShaders/CursorTrail.hlsl is a copy for users to tweak; keep them in sync.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float Time;
    float Scale;
    float2 Resolution;
    float4 Background;
    // x, y, width, height in pixels, same space as SV_POSITION.
    float4 CursorCurrent;
    float4 CursorPrevious;
    // Premultiplied.
    float4 CursorColor;
    // Seconds since the cursor moved.
    float CursorElapsed;
};

// Seconds until the leading and the trailing edge reach the new position.
static const float LEAD = 0.08;
static const float TAIL = 0.24;
static const float OPACITY = 0.8;
// How far the tail fades out: 0 keeps it solid, 1 makes its end fully transparent.
static const float TAIL_FADE = 0.75;
// Motion blur: coverage is averaged over this many seconds before each frame,
// like a camera shutter. 1/60 s gives a soft but readable smear.
static const float SHUTTER = 1.0 / 60.0;
static const int SAMPLES = 6;

float easeOutCubic(float t)
{
    t = 1.0 - saturate(t);
    return 1.0 - t * t * t;
}

// Positive inside a clockwise (in y-down space) edge, in pixels.
float edgeDistance(float2 a, float2 b, float2 p)
{
    const float2 e = b - a;
    const float len = length(e);
    return len < 1e-3 ? 1e6 : (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / len;
}

// Coverage of the trail quad at time t, with a 1px antialiased edge.
float coverageAt(float t, float2 p, float2 from, float2 to, float2 dir)
{
    const float lead = easeOutCubic(t / LEAD);
    const float tail = easeOutCubic(t / TAIL);

    // Clockwise in y-down space: top-left, top-right, bottom-right, bottom-left.
    const float2 signs[4] = { float2(-1, -1), float2(1, -1), float2(1, 1), float2(-1, 1) };
    float2 corners[4];
    [unroll] for (int i = 0; i < 4; i++)
    {
        const float2 a = from + signs[i] * CursorPrevious.zw * 0.5;
        const float2 b = to + signs[i] * CursorCurrent.zw * 0.5;
        // Corners facing the direction of motion lead, the opposite ones trail.
        const float facing = saturate(0.5 + 0.5 * dot(normalize(signs[i]), dir));
        corners[i] = lerp(a, b, lerp(tail, lead, facing));
    }

    float d = 1e6;
    [unroll] for (int j = 0; j < 4; j++)
    {
        d = min(d, edgeDistance(corners[j], corners[(j + 1) % 4], p));
    }
    return saturate(d + 0.5);
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    const float4 color = shaderTexture.Sample(samplerState, tex);
    const float2 p = pos.xy;

    // The real cursor is drawn by the terminal. Painting over it would hide
    // the glyph under a block cursor.
    const bool onCursor = all(p >= CursorCurrent.xy) && all(p < CursorCurrent.xy + CursorCurrent.zw);
    if (CursorElapsed >= TAIL + SHUTTER || onCursor)
    {
        return color;
    }

    const float2 from = CursorPrevious.xy + CursorPrevious.zw * 0.5;
    const float2 to = CursorCurrent.xy + CursorCurrent.zw * 0.5;
    const float2 delta = to - from;
    const float dist = length(delta);
    const float2 dir = dist > 1e-3 ? delta / dist : float2(0, 0);

    float coverage = 0;
    [unroll] for (int k = 0; k < SAMPLES; k++)
    {
        const float t = max(CursorElapsed - SHUTTER * k / (SAMPLES - 1), 0.0);
        coverage += coverageAt(t, p, from, to, dir);
    }
    coverage /= SAMPLES;

    // 1 at the head, 0 at the old position.
    const float along = dist > 1e-3 ? saturate(dot(p - from, dir) / dist) : 1.0;
    coverage *= OPACITY * (1.0 - TAIL_FADE * (1.0 - along));

    return lerp(color, float4(CursorColor.rgb, 1.0), coverage);
}
