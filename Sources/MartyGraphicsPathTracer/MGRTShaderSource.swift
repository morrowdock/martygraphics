// SPDX-License-Identifier: Apache-2.0

/// Metal Shading Language source for the path tracer, compiled at runtime with
/// `MTLDevice.makeLibrary(source:options:)`. The math mirrors `MGRTSampling`.
enum MGRTShaderSource {
    static let source = #"""
#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace metal::raytracing;

constant float PI_F = 3.14159265358979323846f;
constant float INV_PI_F = 0.31830988618379067154f;
constant uint KIND_DIFFUSE = 0u;
constant uint KIND_METAL = 1u;
constant uint KIND_PLASTIC = 2u;
constant uint KIND_GLASS = 3u;
constant uint KIND_EMISSIVE = 4u;
constant uint HALTON_PRIMES[8] = {2u, 3u, 5u, 7u, 11u, 13u, 17u, 19u};

struct Uniforms {
    float4 camPos;   // xyz position, w lens radius
    float4 camU;     // xyz right, w focus distance
    float4 camV;     // xyz up, w tan(half vertical fov)
    float4 camW;     // xyz forward, w aspect
    uint4 size;      // width, height, tile x, tile y
    uint4 frame;     // sample index, seed, max bounces, light count
    uint4 envInfo;   // env width, env height, flags, instance count
    float4 params;   // env intensity, indirect clamp, p(env), unused
};

struct Material { float4 a; float4 b; float4 c; float4 d; float4 e; };
struct AreaLight { float4 corner; float4 edgeU; float4 edgeV; float4 radiance; float4 normal; };
struct InstanceData { float4x4 model; float4x4 normalMatrix; uint4 info; };

struct PostUniforms {
    uint4 size;      // width, height, step, samples
    float4 params;   // sigma luminance, sigma normal, sigma depth, exposure
    float4 params2;  // vignette, bloom, denoise flag, albedo sigma
};

// ---------------------------------------------------------------- random numbers
inline uint pcg_hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

inline float rnd(thread uint& s) {
    s = s * 747796405u + 2891336453u;
    uint word = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    word = (word >> 22u) ^ word;
    return float(word >> 8u) * (1.0f / 16777216.0f);
}

inline float radical_inverse(uint base, uint n) {
    float invBase = 1.0f / float(base);
    float f = invBase;
    float r = 0.0f;
    while (n > 0u) {
        r += f * float(n % base);
        n /= base;
        f *= invBase;
    }
    return min(r, 0.99999994f);
}

struct Sampler { uint rng; uint index; uint pixelHash; };

// Cranley-Patterson rotated Halton point for the first eight dimensions of each pixel.
inline float ld(thread Sampler& s, uint dim) {
    float r = radical_inverse(HALTON_PRIMES[dim], s.index);
    float rot = float(pcg_hash(s.pixelHash + dim * 0x68bc21ebu) >> 8u) * (1.0f / 16777216.0f);
    float x = r + rot;
    x -= floor(x);
    return min(x, 0.99999994f);
}

// ---------------------------------------------------------------- warps and frames
inline float2 concentric_disk(float2 u) {
    float2 o = 2.0f * u - 1.0f;
    if (o.x == 0.0f && o.y == 0.0f) { return float2(0.0f); }
    float r, theta;
    if (fabs(o.x) > fabs(o.y)) { r = o.x; theta = (PI_F / 4.0f) * (o.y / o.x); }
    else { r = o.y; theta = PI_F / 2.0f - (PI_F / 4.0f) * (o.x / o.y); }
    return r * float2(cos(theta), sin(theta));
}

inline float3 cosine_hemisphere(float2 u) {
    float2 d = concentric_disk(u);
    return float3(d.x, d.y, sqrt(max(0.0f, 1.0f - dot(d, d))));
}

inline float tent(float u) {
    float x = 2.0f * u;
    return x < 1.0f ? sqrt(x) - 1.0f : 1.0f - sqrt(2.0f - x);
}

struct Frame { float3 t; float3 b; float3 n; };

inline Frame make_frame(float3 n, float3 hint) {
    Frame f;
    f.n = n;
    float3 t = hint - n * dot(n, hint);
    float len2 = dot(t, t);
    if (len2 < 1e-8f) {
        float sgn = n.z >= 0.0f ? 1.0f : -1.0f;
        float a = -1.0f / (sgn + n.z);
        float b = n.x * n.y * a;
        t = float3(1.0f + sgn * n.x * n.x * a, sgn * b, -sgn * n.x);
    } else {
        t *= rsqrt(len2);
    }
    f.t = t;
    f.b = cross(n, t);
    return f;
}

inline float3 to_local(Frame f, float3 v) { return float3(dot(v, f.t), dot(v, f.b), dot(v, f.n)); }
inline float3 to_world(Frame f, float3 v) { return v.x * f.t + v.y * f.b + v.z * f.n; }

// Wächter & Binder, "A Fast and Robust Method for Avoiding Self-Intersection" (Ray Tracing Gems, 2019).
inline float3 offset_ray(float3 p, float3 n) {
    const float origin = 1.0f / 32.0f;
    const float floatScale = 1.0f / 65536.0f;
    const float intScale = 256.0f;
    int3 ofi = int3(intScale * n);
    float3 pi = float3(as_type<float>(as_type<int>(p.x) + (p.x < 0.0f ? -ofi.x : ofi.x)),
                       as_type<float>(as_type<int>(p.y) + (p.y < 0.0f ? -ofi.y : ofi.y)),
                       as_type<float>(as_type<int>(p.z) + (p.z < 0.0f ? -ofi.z : ofi.z)));
    return float3(fabs(p.x) < origin ? p.x + floatScale * n.x : pi.x,
                  fabs(p.y) < origin ? p.y + floatScale * n.y : pi.y,
                  fabs(p.z) < origin ? p.z + floatScale * n.z : pi.z);
}

inline float luminance(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }
inline float max3(float3 v) { return max(v.x, max(v.y, v.z)); }
inline float power_heuristic(float a, float b) { float a2 = a * a, b2 = b * b; return a2 + b2 > 0.0f ? a2 / (a2 + b2) : 0.0f; }

// ---------------------------------------------------------------- microfacet
inline float ggx_D(float3 m, float2 al) {
    if (m.z <= 0.0f) { return 0.0f; }
    float t = m.x * m.x / (al.x * al.x) + m.y * m.y / (al.y * al.y) + m.z * m.z;
    return 1.0f / (PI_F * al.x * al.y * t * t);
}

inline float ggx_lambda(float3 w, float2 al) {
    float z2 = w.z * w.z;
    if (z2 <= 0.0f) { return 1e30f; }
    float a2 = (al.x * al.x * w.x * w.x + al.y * al.y * w.y * w.y) / z2;
    return 0.5f * (-1.0f + sqrt(1.0f + a2));
}

inline float ggx_G1(float3 w, float2 al) { return 1.0f / (1.0f + ggx_lambda(w, al)); }
inline float ggx_G2(float3 wo, float3 wi, float2 al) { return 1.0f / (1.0f + ggx_lambda(wo, al) + ggx_lambda(wi, al)); }

inline float3 sample_vndf(float3 wo, float2 al, float2 u) {
    float3 vh = normalize(float3(al.x * wo.x, al.y * wo.y, wo.z));
    float lensq = vh.x * vh.x + vh.y * vh.y;
    float3 t1 = lensq > 0.0f ? float3(-vh.y, vh.x, 0.0f) * rsqrt(lensq) : float3(1.0f, 0.0f, 0.0f);
    float3 t2 = cross(vh, t1);
    float r = sqrt(u.x);
    float phi = 2.0f * PI_F * u.y;
    float p1 = r * cos(phi);
    float p2 = r * sin(phi);
    float s = 0.5f * (1.0f + vh.z);
    p2 = (1.0f - s) * sqrt(max(0.0f, 1.0f - p1 * p1)) + s * p2;
    float3 nh = p1 * t1 + p2 * t2 + sqrt(max(0.0f, 1.0f - p1 * p1 - p2 * p2)) * vh;
    return normalize(float3(al.x * nh.x, al.y * nh.y, max(1e-6f, nh.z)));
}

inline float ggx_reflect_pdf(float3 wo, float3 wi, float2 al) {
    if (wo.z <= 0.0f) { return 0.0f; }
    float3 hs = wo + wi;
    if (dot(hs, hs) <= 0.0f) { return 0.0f; }
    float3 m = normalize(hs);
    if (m.z <= 0.0f || dot(wo, m) <= 0.0f) { return 0.0f; }
    return ggx_G1(wo, al) * ggx_D(m, al) / (4.0f * wo.z);
}

inline float fresnel_dielectric(float cosI, float eta) {
    float c = clamp(cosI, 0.0f, 1.0f);
    float sin2T = (1.0f - c * c) / (eta * eta);
    if (sin2T >= 1.0f) { return 1.0f; }
    float cosT = sqrt(1.0f - sin2T);
    float rs = (c - eta * cosT) / (c + eta * cosT);
    float rp = (eta * c - cosT) / (eta * c + cosT);
    return 0.5f * (rs * rs + rp * rp);
}

// Signed version: a negative cosine means the incident ray is inside the denser medium.
inline float fresnel_signed(float cosI, float eta) {
    return cosI < 0.0f ? fresnel_dielectric(-cosI, 1.0f / eta) : fresnel_dielectric(cosI, eta);
}

inline float3 schlick(float3 f0, float c) {
    float m = pow(1.0f - clamp(c, 0.0f, 1.0f), 5.0f);
    return f0 + (1.0f - f0) * m;
}

// ---------------------------------------------------------------- materials
struct Mat {
    uint kind; float3 base; float2 alpha; float ior; float coat; float2 coatAlpha; float spec; float3 emission;
};

inline float2 alphas(float roughness, float aniso) {
    float a = max(roughness * roughness, 0.002f);
    float aspect = sqrt(1.0f - 0.9f * clamp(aniso, 0.0f, 0.95f));
    return float2(max(a / aspect, 0.002f), max(a * aspect, 0.002f));
}

inline Mat load_mat(Material m) {
    Mat r;
    r.base = m.a.xyz;
    r.kind = uint(m.a.w + 0.5f);
    r.alpha = alphas(m.b.x, m.b.y);
    r.ior = m.b.z;
    r.coat = m.b.w;
    r.coatAlpha = alphas(m.c.x, 0.0f);
    r.spec = m.c.y;
    r.emission = m.d.xyz;
    return r;
}

struct Lobes { float coat; float spec; float diff; };

inline Lobes lobe_probs(Mat m, float3 wo) {
    Lobes l;
    float pc = 0.0f;
    if (m.coat > 0.0f) { pc = max(m.coat * fresnel_dielectric(wo.z, 1.5f), 0.12f * m.coat); }
    float ps = 0.0f, pd = 0.0f;
    if (m.kind == KIND_METAL) { ps = 1.0f; }
    else if (m.kind == KIND_PLASTIC) {
        float F = m.spec * fresnel_dielectric(wo.z, m.ior);
        float ws = m.spec > 0.0f ? max(F, 0.08f * m.spec) : 0.0f;
        float wd = max(luminance(m.base), 0.02f) * (1.0f - F);
        ps = ws / (ws + wd);
        pd = 1.0f - ps;
    } else { pd = 1.0f; }
    l.coat = pc;
    l.spec = ps * (1.0f - pc);
    l.diff = pd * (1.0f - pc);
    return l;
}

inline float3 eval_opaque(Mat m, float3 wo, float3 wi, thread float& pdf) {
    pdf = 0.0f;
    if (wo.z <= 0.0f || wi.z <= 0.0f) { return float3(0.0f); }
    Lobes l = lobe_probs(m, wo);
    float3 h = normalize(wo + wi);
    float denom = 4.0f * wo.z * wi.z;
    float3 f = float3(0.0f);
    float atten = 1.0f;
    if (m.coat > 0.0f) {
        float fc = m.coat * fresnel_dielectric(dot(wi, h), 1.5f);
        f += float3(fc * ggx_D(h, m.coatAlpha) * ggx_G2(wo, wi, m.coatAlpha) / denom);
        pdf += l.coat * ggx_reflect_pdf(wo, wi, m.coatAlpha);
        atten = (1.0f - m.coat * fresnel_dielectric(wo.z, 1.5f)) * (1.0f - m.coat * fresnel_dielectric(wi.z, 1.5f));
    }
    if (m.kind == KIND_METAL) {
        float3 F = schlick(m.base, dot(wi, h));
        f += atten * F * (ggx_D(h, m.alpha) * ggx_G2(wo, wi, m.alpha) / denom);
        pdf += l.spec * ggx_reflect_pdf(wo, wi, m.alpha);
    } else if (m.kind == KIND_PLASTIC) {
        float fs = m.spec * fresnel_dielectric(dot(wi, h), m.ior);
        f += float3(atten * fs * ggx_D(h, m.alpha) * ggx_G2(wo, wi, m.alpha) / denom);
        pdf += l.spec * ggx_reflect_pdf(wo, wi, m.alpha);
        float fo = m.spec * fresnel_dielectric(wo.z, m.ior);
        float fi = m.spec * fresnel_dielectric(wi.z, m.ior);
        f += atten * m.base * INV_PI_F * (1.0f - fo) * (1.0f - fi);
        pdf += l.diff * wi.z * INV_PI_F;
    } else {
        f += atten * m.base * INV_PI_F;
        pdf += l.diff * wi.z * INV_PI_F;
    }
    return f;
}

struct BSample { float3 wi; float3 f; float pdf; bool delta; };

inline BSample sample_opaque(Mat m, float3 wo, float3 u) {
    BSample s;
    s.delta = false; s.pdf = 0.0f; s.f = float3(0.0f); s.wi = float3(0.0f, 0.0f, 1.0f);
    if (wo.z <= 0.0f) { return s; }
    Lobes l = lobe_probs(m, wo);
    float3 wi;
    if (u.x < l.coat) {
        float3 h = sample_vndf(wo, m.coatAlpha, u.yz);
        wi = 2.0f * dot(wo, h) * h - wo;
    } else if (u.x < l.coat + l.spec) {
        float3 h = sample_vndf(wo, m.alpha, u.yz);
        wi = 2.0f * dot(wo, h) * h - wo;
    } else {
        wi = cosine_hemisphere(u.yz);
    }
    if (wi.z <= 0.0f) { return s; }
    s.wi = wi;
    s.f = eval_opaque(m, wo, wi, s.pdf);
    return s;
}

inline bool is_smooth_glass(Mat m) { return m.alpha.x < 0.0035f && m.alpha.y < 0.0035f; }

inline float vndf_pdf_abs(float3 w, float3 wm, float2 al) {
    float c = fabs(w.z);
    if (c <= 0.0f) { return 0.0f; }
    return ggx_G1(w, al) / c * ggx_D(wm, al) * fabs(dot(w, wm));
}

// Rough dielectric (Walter et al. 2007; pbrt-v4 conventions). Local frame, z = outward normal.
inline float3 eval_glass(Mat m, float3 wo, float3 wi, thread float& pdf) {
    pdf = 0.0f;
    if (is_smooth_glass(m)) { return float3(0.0f); }
    float cosO = wo.z, cosI = wi.z;
    if (cosO == 0.0f || cosI == 0.0f) { return float3(0.0f); }
    bool refl = cosO * cosI > 0.0f;
    float etap = 1.0f;
    if (!refl) { etap = cosO > 0.0f ? m.ior : 1.0f / m.ior; }
    float3 wm = wi * etap + wo;
    if (dot(wm, wm) == 0.0f) { return float3(0.0f); }
    wm = normalize(wm);
    if (wm.z < 0.0f) { wm = -wm; }
    if (dot(wm, wi) * cosI < 0.0f || dot(wm, wo) * cosO < 0.0f) { return float3(0.0f); }
    float R = fresnel_signed(dot(wo, wm), m.ior);
    float T = 1.0f - R;
    float D = ggx_D(wm, m.alpha);
    float G = ggx_G2(wo, wi, m.alpha);
    if (refl) {
        pdf = vndf_pdf_abs(wo, wm, m.alpha) / (4.0f * fabs(dot(wo, wm))) * R;
        return float3(D * G * R / fabs(4.0f * cosI * cosO));
    }
    float sq = dot(wi, wm) + dot(wo, wm) / etap;
    float denom = sq * sq * cosI * cosO;
    if (denom == 0.0f) { return float3(0.0f); }
    float ft = T * D * G * fabs(dot(wi, wm) * dot(wo, wm) / denom) / (etap * etap);
    float dwm = fabs(dot(wi, wm)) / (sq * sq);
    pdf = vndf_pdf_abs(wo, wm, m.alpha) * dwm * T;
    return m.base * ft;
}

inline bool refract_dir(float3 wi, float3 n, float eta, thread float3& wt) {
    float cosI = dot(n, wi);
    if (cosI < 0.0f) { eta = 1.0f / eta; cosI = -cosI; n = -n; }
    float sin2I = max(0.0f, 1.0f - cosI * cosI);
    float sin2T = sin2I / (eta * eta);
    if (sin2T >= 1.0f) { return false; }
    float cosT = sqrt(1.0f - sin2T);
    wt = -wi / eta + (cosI / eta - cosT) * n;
    return true;
}

inline BSample sample_glass(Mat m, float3 wo, float3 u) {
    BSample s;
    s.delta = false; s.pdf = 0.0f; s.f = float3(0.0f); s.wi = float3(0.0f, 0.0f, 1.0f);
    if (wo.z == 0.0f) { return s; }
    if (is_smooth_glass(m)) {
        float R = fresnel_signed(wo.z, m.ior);
        s.delta = true;
        if (u.x < R) {
            s.wi = float3(-wo.x, -wo.y, wo.z);
            s.pdf = R;
            s.f = float3(R / fabs(s.wi.z));
            return s;
        }
        float3 wt;
        if (!refract_dir(wo, float3(0.0f, 0.0f, 1.0f), m.ior, wt)) { return s; }
        float etap = wo.z > 0.0f ? m.ior : 1.0f / m.ior;
        s.wi = wt;
        s.pdf = 1.0f - R;
        s.f = m.base * ((1.0f - R) / (fabs(wt.z) * etap * etap));
        return s;
    }
    float3 woUp = wo.z >= 0.0f ? wo : -wo;
    float3 wm = sample_vndf(woUp, m.alpha, u.yz);
    float R = fresnel_signed(dot(wo, wm), m.ior);
    float3 wi;
    if (u.x < R) {
        wi = 2.0f * dot(wo, wm) * wm - wo;
        if (wo.z * wi.z <= 0.0f) { return s; }
    } else {
        if (!refract_dir(wo, wm, m.ior, wi)) { return s; }
        if (wo.z * wi.z >= 0.0f || wi.z == 0.0f) { return s; }
    }
    s.wi = wi;
    s.f = eval_glass(m, wo, wi, s.pdf);
    return s;
}

inline float3 albedo_of(Mat m) {
    if (m.kind == KIND_GLASS) { return float3(1.0f); }
    return m.base;
}

// ---------------------------------------------------------------- environment
inline float2 env_uv(float3 d) {
    float u = atan2(d.z, d.x) / (2.0f * PI_F) + 0.5f;
    float v = acos(clamp(d.y, -1.0f, 1.0f)) / PI_F;
    return float2(u - floor(u), clamp(v, 0.0f, 1.0f));
}

inline float3 env_dir(float u, float v) {
    float phi = 2.0f * PI_F * (u - 0.5f);
    float theta = PI_F * v;
    return float3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi));
}

inline float3 env_eval(texture2d<float> tex, float3 d, float intensity) {
    constexpr sampler s(address::repeat, filter::linear, coord::normalized);
    float2 uv = env_uv(d);
    return tex.sample(s, uv, level(0.0f)).xyz * intensity;
}

inline uint cdf_search(device const float* cdf, uint count, float u) {
    uint lo = 0u, hi = count - 1u;
    while (lo < hi) {
        uint mid = (lo + hi + 1u) >> 1u;
        if (cdf[mid] <= u) { lo = mid; } else { hi = mid - 1u; }
    }
    return lo;
}

inline float env_pdf(device const float* pdfUV, uint w, uint h, float3 d) {
    float2 uv = env_uv(d);
    uint i = min(w - 1u, uint(uv.x * float(w)));
    uint j = min(h - 1u, uint(uv.y * float(h)));
    float sinTheta = sqrt(max(0.0f, 1.0f - d.y * d.y));
    if (sinTheta <= 1e-6f) { return 0.0f; }
    return pdfUV[j * w + i] / (2.0f * PI_F * PI_F * sinTheta);
}

struct LightSample { float3 wi; float dist; float3 Le; float pdf; };

inline LightSample sample_lights(constant Uniforms& U, device const AreaLight* lights,
                                 device const float* marginal, device const float* conditional,
                                 device const float* pdfUV, texture2d<float> envTex,
                                 float3 P, float sel, float2 u) {
    LightSample ls;
    ls.pdf = 0.0f; ls.Le = float3(0.0f); ls.dist = INFINITY; ls.wi = float3(0.0f, 1.0f, 0.0f);
    float pEnv = U.params.z;
    uint W = U.envInfo.x, H = U.envInfo.y;
    if (sel < pEnv) {
        uint j = cdf_search(marginal, H, u.y);
        float m0 = marginal[j], m1 = marginal[j + 1u];
        float dv = m1 > m0 ? (u.y - m0) / (m1 - m0) : 0.5f;
        device const float* row = conditional + j * (W + 1u);
        uint i = cdf_search(row, W, u.x);
        float c0 = row[i], c1 = row[i + 1u];
        float du = c1 > c0 ? (u.x - c0) / (c1 - c0) : 0.5f;
        float uu = (float(i) + du) / float(W);
        float vv = (float(j) + dv) / float(H);
        float sinTheta = sin(PI_F * vv);
        if (sinTheta <= 1e-6f) { return ls; }
        ls.wi = env_dir(uu, vv);
        ls.pdf = pEnv * pdfUV[j * W + i] / (2.0f * PI_F * PI_F * sinTheta);
        ls.Le = env_eval(envTex, ls.wi, U.params.x);
        return ls;
    }
    // Pick an area light by power.
    float x = (sel - pEnv) / max(1.0f - pEnv, 1e-6f);
    uint n = U.frame.w;
    uint li = n - 1u;
    float acc = 0.0f;
    for (uint k = 0u; k < n; ++k) {
        acc += lights[k].corner.w;
        if (x < acc) { li = k; break; }
    }
    AreaLight L = lights[li];
    float3 q = L.corner.xyz + u.x * L.edgeU.xyz + u.y * L.edgeV.xyz;
    float3 d = q - P;
    float d2 = dot(d, d);
    if (d2 <= 1e-10f) { return ls; }
    float dist = sqrt(d2);
    float3 wi = d / dist;
    float cosL = -dot(wi, L.normal.xyz);
    if (cosL <= 0.0f) { return ls; }
    ls.wi = wi;
    ls.dist = dist;
    ls.Le = L.radiance.xyz;
    ls.pdf = (1.0f - pEnv) * L.corner.w * d2 / (cosL * L.edgeU.w);
    return ls;
}

inline void add_clamped(thread float3& L, float3 c, uint level, float clampLum) {
    if (level >= 2u && clampLum > 0.0f) {
        float l = luminance(c);
        if (l > clampLum) { c *= clampLum / l; }
    }
    L += c;
}

// ---------------------------------------------------------------- path tracing kernel
kernel void pathtrace(uint2 tid [[thread_position_in_grid]],
                      constant Uniforms& U [[buffer(0)]],
                      acceleration_structure<instancing> accel [[buffer(1)]],
                      device const InstanceData* instances [[buffer(2)]],
                      device const float4* positions [[buffer(3)]],
                      device const float4* normals [[buffer(4)]],
                      device const float4* tangents [[buffer(5)]],
                      device const uint* indices [[buffer(6)]],
                      device const uint* triMaterial [[buffer(7)]],
                      device const Material* materials [[buffer(8)]],
                      device const AreaLight* lights [[buffer(9)]],
                      device const float* envMarginal [[buffer(10)]],
                      device const float* envConditional [[buffer(11)]],
                      device const float* envPdf [[buffer(12)]],
                      device float4* accum [[buffer(13)]],
                      device float4* aovAlbedo [[buffer(14)]],
                      device float4* aovNormal [[buffer(15)]],
                      texture2d<float> envTex [[texture(0)]]) {
    uint2 pix = tid + U.size.zw;
    uint W = U.size.x, H = U.size.y;
    if (pix.x >= W || pix.y >= H) { return; }
    uint idx = pix.y * W + pix.x;

    Sampler smp;
    smp.index = U.frame.x + 1u;
    smp.pixelHash = pcg_hash(idx + pcg_hash(U.frame.y));
    smp.rng = pcg_hash(smp.pixelHash ^ pcg_hash(U.frame.x + 0x9E3779B9u));

    // Camera ray: tent-filtered pixel jitter and a thin lens.
    float2 jitter = float2(0.5f + 0.75f * tent(ld(smp, 0u)), 0.5f + 0.75f * tent(ld(smp, 1u)));
    float2 ndc = float2((float(pix.x) + jitter.x) / float(W) * 2.0f - 1.0f,
                        1.0f - (float(pix.y) + jitter.y) / float(H) * 2.0f);
    float3 camU = U.camU.xyz, camV = U.camV.xyz, camW = U.camW.xyz;
    float3 dir = normalize(camW + ndc.x * U.camV.w * U.camW.w * camU + ndc.y * U.camV.w * camV);
    float3 org = U.camPos.xyz;
    if (U.camPos.w > 0.0f) {
        float3 focus = org + dir * (U.camU.w / dot(dir, camW));
        float2 disk = concentric_disk(float2(ld(smp, 2u), ld(smp, 3u))) * U.camPos.w;
        org = U.camPos.xyz + disk.x * camU + disk.y * camV;
        dir = normalize(focus - org);
    }

    intersector<triangle_data, instancing> isect;
    isect.assume_geometry_type(geometry_type::triangle);
    isect.force_opacity(forced_opacity::opaque);
    intersector<triangle_data, instancing> shadow;
    shadow.assume_geometry_type(geometry_type::triangle);
    shadow.force_opacity(forced_opacity::opaque);
    shadow.accept_any_intersection(true);

    ray r;
    r.origin = org;
    r.direction = dir;
    r.min_distance = 0.0f;
    r.max_distance = INFINITY;

    float3 L = float3(0.0f);
    float3 beta = float3(1.0f);
    float prevPdf = 0.0f;
    bool prevDelta = true;
    float3 aovAlb = float3(1.0f);
    float3 aovN = float3(0.0f);
    float aovDepth = 1e4f;
    bool aovDone = false;
    float3 aovThroughput = float3(1.0f);
    float pathLen = 0.0f;
    uint maxBounces = U.frame.z;
    uint nLights = U.frame.w;
    float clampLum = U.params.y;
    float pEnv = U.params.z;
    bool regularize = false;

    for (uint depth = 0u; depth <= maxBounces; ++depth) {
        intersection_result<triangle_data, instancing> hit = isect.intersect(r, accel, 0xFFu);
        float tHit = hit.type == intersection_type::none ? INFINITY : hit.distance;

        int lightHit = -1;
        float tLight = tHit;
        for (uint li = 0u; li < nLights; ++li) {
            AreaLight A = lights[li];
            if (depth == 0u && A.edgeV.w < 0.5f) { continue; }
            float dn = dot(r.direction, A.normal.xyz);
            if (dn >= 0.0f) { continue; }
            float t = dot(A.corner.xyz - r.origin, A.normal.xyz) / dn;
            if (t <= 1e-4f || t >= tLight) { continue; }
            float3 q = r.origin + t * r.direction - A.corner.xyz;
            float a = dot(q, A.edgeU.xyz) / dot(A.edgeU.xyz, A.edgeU.xyz);
            float b = dot(q, A.edgeV.xyz) / dot(A.edgeV.xyz, A.edgeV.xyz);
            if (a < 0.0f || a > 1.0f || b < 0.0f || b > 1.0f) { continue; }
            tLight = t;
            lightHit = int(li);
        }

        if (lightHit >= 0) {
            AreaLight A = lights[lightHit];
            float w = 1.0f;
            if (!prevDelta && depth > 0u) {
                float cosL = -dot(r.direction, A.normal.xyz);
                float lp = (1.0f - pEnv) * A.corner.w * tLight * tLight / (cosL * A.edgeU.w);
                w = power_heuristic(prevPdf, lp);
            }
            add_clamped(L, beta * A.radiance.xyz * w, depth, clampLum);
            if (!aovDone) { aovAlb = aovThroughput; aovN = float3(0.0f); aovDepth = pathLen + tLight; aovDone = true; }
            break;
        }

        if (hit.type == intersection_type::none) {
            float3 Le = env_eval(envTex, r.direction, U.params.x);
            float w = 1.0f;
            if (!prevDelta && depth > 0u && pEnv > 0.0f) {
                w = power_heuristic(prevPdf, pEnv * env_pdf(envPdf, U.envInfo.x, U.envInfo.y, r.direction));
            }
            if ((U.envInfo.z & 1u) != 0u && depth > 0u) { w = 1.0f; }
            if ((U.envInfo.z & 2u) != 0u && depth > 0u) { w = 0.0f; }
            add_clamped(L, beta * Le * w, depth, clampLum);
            if (!aovDone) { aovAlb = aovThroughput; aovN = float3(0.0f); aovDepth = 1e4f; aovDone = true; }
            break;
        }

        InstanceData inst = instances[hit.instance_id];
        uint tri = inst.info.y + hit.primitive_id;
        uint i0 = indices[3u * tri] + inst.info.x;
        uint i1 = indices[3u * tri + 1u] + inst.info.x;
        uint i2 = indices[3u * tri + 2u] + inst.info.x;
        float2 bc = hit.triangle_barycentric_coord;
        float w0 = 1.0f - bc.x - bc.y;
        float3 p0 = positions[i0].xyz, p1 = positions[i1].xyz, p2 = positions[i2].xyz;
        float3x3 nm = float3x3(inst.normalMatrix[0].xyz, inst.normalMatrix[1].xyz, inst.normalMatrix[2].xyz);
        float3x3 mm = float3x3(inst.model[0].xyz, inst.model[1].xyz, inst.model[2].xyz);
        float3 Ng = normalize(nm * cross(p1 - p0, p2 - p0));
        float3 Ns = nm * (w0 * normals[i0].xyz + bc.x * normals[i1].xyz + bc.y * normals[i2].xyz);
        Ns = dot(Ns, Ns) > 1e-12f ? normalize(Ns) : Ng;
        float3 T = mm * (w0 * tangents[i0].xyz + bc.x * tangents[i1].xyz + bc.y * tangents[i2].xyz);
        float3 P = r.origin + r.direction * hit.distance;
        pathLen += hit.distance;
        // The intersector's error grows with triangle size, so large triangles (floors) need a
        // proportionally larger push-off than the position-based offset alone provides.
        float triEps = 2e-6f * (max(length(p1 - p0), length(p2 - p0)) + max3(fabs(P)));

        Mat m = load_mat(materials[triMaterial[tri]]);
        // Path regularisation (as in pbrt-v4): once the path has scattered off a non-specular
        // surface, near-mirror lobes are widened. Primary-hit appearance is unchanged; noisy
        // glossy-to-glossy chains converge much faster at a small, smooth bias.
        if (regularize && (U.envInfo.z & 16u) == 0u) {
            if (m.alpha.x < 0.3f) { m.alpha.x = clamp(2.0f * m.alpha.x, 0.1f, 0.3f); }
            if (m.alpha.y < 0.3f) { m.alpha.y = clamp(2.0f * m.alpha.y, 0.1f, 0.3f); }
            if (m.coatAlpha.x < 0.3f) { m.coatAlpha = float2(clamp(2.0f * m.coatAlpha.x, 0.1f, 0.3f)); }
        }
        float3 wo = -r.direction;
        if (max3(m.emission) > 0.0f) { add_clamped(L, beta * m.emission, depth, clampLum); }
        if (m.kind == KIND_EMISSIVE) {
            if (!aovDone) { aovAlb = aovThroughput; aovN = Ng; aovDepth = pathLen; aovDone = true; }
            break;
        }

        bool glass = m.kind == KIND_GLASS;
        if (dot(Ns, Ng) < 0.0f) { Ns = -Ns; }
        if (!glass) {
            if (dot(Ng, wo) < 0.0f) { Ng = -Ng; Ns = -Ns; }
            if (dot(Ns, wo) <= 1e-4f) { Ns = Ng; }
        }
        Frame fr = make_frame(Ns, T);
        float3 woL = to_local(fr, wo);
        if ((U.envInfo.z & 4u) != 0u) { L = Ns * 0.5f + 0.5f; break; }
        if ((U.envInfo.z & 8u) != 0u) { L = Ng * 0.5f + 0.5f; break; }

        if (!aovDone) {
            bool mirrorLike = (m.kind == KIND_METAL && max(m.alpha.x, m.alpha.y) < 0.012f) || (glass && m.alpha.x < 0.012f);
            if (mirrorLike && depth < 2u) {
                aovThroughput *= glass ? float3(1.0f) : m.base;
            } else {
                aovAlb = aovThroughput * albedo_of(m);
                aovN = Ns;
                aovDepth = pathLen;
                aovDone = true;
            }
        }

        bool delta = glass && is_smooth_glass(m);
        if (!delta && (pEnv > 0.0f || nLights > 0u) && (U.envInfo.z & 1u) == 0u) {
            float sel = rnd(smp.rng);
            float2 lu = depth == 0u ? float2(ld(smp, 4u), ld(smp, 5u)) : float2(rnd(smp.rng), rnd(smp.rng));
            LightSample ls = sample_lights(U, lights, envMarginal, envConditional, envPdf, envTex, P, sel, lu);
            if (ls.pdf > 0.0f && max3(ls.Le) > 0.0f) {
                float3 wiL = to_local(fr, ls.wi);
                float bpdf = 0.0f;
                float3 f = glass ? eval_glass(m, woL, wiL, bpdf) : eval_opaque(m, woL, wiL, bpdf);
                bool sideOK = glass || dot(ls.wi, Ng) > 0.0f;
                if (sideOK && max3(f) > 0.0f) {
                    ray sr;
                    float3 nOff = dot(ls.wi, Ng) > 0.0f ? Ng : -Ng;
                    sr.origin = offset_ray(P, nOff) + nOff * triEps;
                    sr.direction = ls.wi;
                    sr.min_distance = 0.0f;
                    sr.max_distance = isinf(ls.dist) ? INFINITY : ls.dist * 0.9999f;
                    intersection_result<triangle_data, instancing> sh = shadow.intersect(sr, accel, 0xFFu);
                    if (sh.type == intersection_type::none) {
                        float w = (U.envInfo.z & 2u) != 0u ? 1.0f : power_heuristic(ls.pdf, bpdf);
                        add_clamped(L, beta * f * fabs(wiL.z) * ls.Le * (w / ls.pdf), depth + 1u, clampLum);
                    }
                }
            }
        }

        float3 u3 = depth == 0u ? float3(rnd(smp.rng), ld(smp, 6u), ld(smp, 7u))
                                : float3(rnd(smp.rng), rnd(smp.rng), rnd(smp.rng));
        BSample bs = glass ? sample_glass(m, woL, u3) : sample_opaque(m, woL, u3);
        if (bs.pdf <= 0.0f || max3(bs.f) <= 0.0f) { break; }
        float3 wi = to_world(fr, bs.wi);
        if (!glass && dot(wi, Ng) <= 0.0f) { break; }
        beta *= bs.f * (fabs(bs.wi.z) / bs.pdf);
        prevPdf = bs.pdf;
        prevDelta = bs.delta;
        if (!bs.delta) { regularize = true; }
        if (depth >= 3u) {
            float q = clamp(max3(beta), 0.05f, 0.95f);
            if (rnd(smp.rng) > q) { break; }
            beta /= q;
        }
        if (!all(isfinite(beta))) { break; }
        float3 nNext = dot(wi, Ng) > 0.0f ? Ng : -Ng;
        r.origin = offset_ray(P, nNext) + nNext * triEps;
        r.direction = wi;
        r.min_distance = 0.0f;
        r.max_distance = INFINITY;
    }

    if (!all(isfinite(L))) { L = float3(0.0f); }
    float l = luminance(L);
    accum[idx] += float4(L, l * l);
    aovAlbedo[idx] += float4(aovAlb, aovDepth);
    aovNormal[idx] += float4(aovN, 0.0f);
}

// ---------------------------------------------------------------- denoise and display
kernel void resolve(uint2 gid [[thread_position_in_grid]],
                    constant PostUniforms& P [[buffer(0)]],
                    device const float4* accum [[buffer(1)]],
                    device const float4* aovAlbedo [[buffer(2)]],
                    device const float4* aovNormal [[buffer(3)]],
                    device float4* irradiance [[buffer(4)]],
                    device float4* guide [[buffer(5)]],
                    device float4* albedo [[buffer(6)]]) {
    uint W = P.size.x, H = P.size.y;
    if (gid.x >= W || gid.y >= H) { return; }
    uint i = gid.y * W + gid.x;
    float n = float(max(P.size.w, 1u));
    float4 a = accum[i];
    float3 mean = a.xyz / n;
    float lm = luminance(mean);
    float var = max(0.0f, a.w / n - lm * lm) / n;
    float4 alb = aovAlbedo[i] / n;
    float3 nrm = aovNormal[i].xyz / n;
    float len = length(nrm);
    nrm = len > 1e-4f ? nrm / len : float3(0.0f);
    float3 safeAlb = max(alb.xyz, float3(0.004f));
    float la = max(luminance(safeAlb), 0.004f);
    irradiance[i] = float4(mean / safeAlb, var / (la * la));
    guide[i] = float4(nrm, alb.w);
    albedo[i] = float4(safeAlb, 0.0f);
}

kernel void atrous(uint2 gid [[thread_position_in_grid]],
                   constant PostUniforms& P [[buffer(0)]],
                   device const float4* src [[buffer(1)]],
                   device float4* dst [[buffer(2)]],
                   device const float4* guide [[buffer(3)]],
                   device const float4* albedo [[buffer(4)]]) {
    int W = int(P.size.x), H = int(P.size.y);
    int2 p = int2(gid);
    if (p.x >= W || p.y >= H) { return; }
    int step = int(P.size.z);
    int ci = p.y * W + p.x;
    float4 c = src[ci];
    float4 g = guide[ci];
    float3 a = albedo[ci].xyz;
    float lc = luminance(c.xyz);

    // 3x3 Gaussian of the variance (SVGF) for a stable luminance edge-stop.
    float varBlur = 0.0f, varW = 0.0f;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            int2 q = clamp(p + int2(dx, dy), int2(0), int2(W - 1, H - 1));
            float k = (dx == 0 ? 2.0f : 1.0f) * (dy == 0 ? 2.0f : 1.0f);
            varBlur += k * src[q.y * W + q.x].w;
            varW += k;
        }
    }
    varBlur /= varW;

    // Screen-space depth gradient for a slope-aware depth weight.
    int2 qx = clamp(p + int2(1, 0), int2(0), int2(W - 1, H - 1));
    int2 qy = clamp(p + int2(0, 1), int2(0), int2(W - 1, H - 1));
    float dz = max(fabs(guide[qx.y * W + qx.x].w - g.w), fabs(guide[qy.y * W + qy.x].w - g.w));
    dz = min(dz, 0.05f * g.w + 1e-3f);

    const float kernelW[3] = {3.0f / 8.0f, 1.0f / 4.0f, 1.0f / 16.0f};
    float sigmaL = P.params.x, sigmaN = P.params.y, sigmaZ = P.params.z, sigmaA = P.params2.w;
    float lumDenom = sigmaL * sqrt(max(varBlur, 0.0f)) + 1e-6f;
    float3 sum = float3(0.0f);
    float sumVar = 0.0f, sumW = 0.0f;
    for (int dy = -2; dy <= 2; ++dy) {
        for (int dx = -2; dx <= 2; ++dx) {
            int2 q = p + int2(dx, dy) * step;
            if (q.x < 0 || q.y < 0 || q.x >= W || q.y >= H) { continue; }
            int qi = q.y * W + q.x;
            float4 cq = src[qi];
            float4 gq = guide[qi];
            float3 aq = albedo[qi].xyz;
            float h = kernelW[abs(dx)] * kernelW[abs(dy)];
            float wn;
            float lenP = dot(g.xyz, g.xyz), lenQ = dot(gq.xyz, gq.xyz);
            if (lenP < 0.25f || lenQ < 0.25f) { wn = (lenP < 0.25f && lenQ < 0.25f) ? 1.0f : 0.0f; }
            else { wn = pow(max(0.0f, dot(g.xyz, gq.xyz)), sigmaN); }
            float dist = length(float2(dx, dy) * float(step));
            float wz = exp(-fabs(g.w - gq.w) / (sigmaZ * dz * dist + 1e-3f * g.w + 1e-5f));
            float wl = exp(-fabs(lc - luminance(cq.xyz)) / lumDenom);
            float3 da = a - aq;
            float wa = exp(-dot(da, da) / (sigmaA * sigmaA * (dot(a, a) + 1e-4f)));
            float w = h * wn * wz * wl * wa;
            sum += w * cq.xyz;
            sumVar += w * w * cq.w;
            sumW += w;
        }
    }
    if (sumW <= 1e-12f) { dst[ci] = c; return; }
    dst[ci] = float4(sum / sumW, sumVar / (sumW * sumW));
}

inline float3 aces_fitted(float3 v) {
    float3x3 inM = float3x3(float3(0.59719f, 0.07600f, 0.02840f),
                            float3(0.35458f, 0.90834f, 0.13383f),
                            float3(0.04823f, 0.01566f, 0.83777f));
    float3x3 outM = float3x3(float3(1.60475f, -0.10208f, -0.00327f),
                             float3(-0.53108f, 1.10813f, -0.07276f),
                             float3(-0.07367f, -0.00605f, 1.07602f));
    v = inM * v;
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return clamp(outM * (a / b), 0.0f, 1.0f);
}

inline float srgb(float x) { return x <= 0.0031308f ? 12.92f * x : 1.055f * pow(x, 1.0f / 2.4f) - 0.055f; }

kernel void compose(uint2 gid [[thread_position_in_grid]],
                    constant PostUniforms& P [[buffer(0)]],
                    device const float4* accum [[buffer(1)]],
                    device const float4* filtered [[buffer(2)]],
                    device const float4* albedo [[buffer(3)]],
                    device float4* hdr [[buffer(4)]]) {
    uint W = P.size.x, H = P.size.y;
    if (gid.x >= W || gid.y >= H) { return; }
    uint i = gid.y * W + gid.x;
    float n = float(max(P.size.w, 1u));
    float3 c = P.params2.z > 0.5f ? filtered[i].xyz * albedo[i].xyz : accum[i].xyz / n;
    hdr[i] = float4(max(c, float3(0.0f)) * exp2(P.params.w), 1.0f);
}

// Separable Gaussian blur of the bright part of the image (glare); direction in size.z (0 = x, 1 = y).
kernel void glare_blur(uint2 gid [[thread_position_in_grid]],
                       constant PostUniforms& P [[buffer(0)]],
                       device const float4* src [[buffer(1)]],
                       device float4* dst [[buffer(2)]]) {
    int W = int(P.size.x), H = int(P.size.y);
    int2 p = int2(gid);
    if (p.x >= W || p.y >= H) { return; }
    int2 axis = P.size.z == 0u ? int2(1, 0) : int2(0, 1);
    float radius = P.params.x;
    int taps = int(ceil(radius * 3.0f));
    float3 sum = float3(0.0f);
    float wsum = 0.0f;
    bool threshold = P.params.y > 0.5f;
    for (int k = -taps; k <= taps; ++k) {
        int2 q = clamp(p + axis * k, int2(0), int2(W - 1, H - 1));
        float3 v = src[q.y * W + q.x].xyz;
        if (threshold) { v = max(v - float3(1.0f), float3(0.0f)); }
        float w = exp(-0.5f * float(k * k) / (radius * radius));
        sum += w * v;
        wsum += w;
    }
    dst[p.y * W + p.x] = float4(sum / wsum, 1.0f);
}

kernel void tonemap(uint2 gid [[thread_position_in_grid]],
                    constant PostUniforms& P [[buffer(0)]],
                    device const float4* hdr [[buffer(1)]],
                    device const float4* glare [[buffer(2)]],
                    device uchar4* out [[buffer(3)]]) {
    uint W = P.size.x, H = P.size.y;
    if (gid.x >= W || gid.y >= H) { return; }
    uint i = gid.y * W + gid.x;
    float3 c = hdr[i].xyz;
    if (P.params2.y > 0.0f) { c += P.params2.y * glare[i].xyz; }
    float2 uv = (float2(gid) + 0.5f) / float2(W, H) - 0.5f;
    uv.x *= float(W) / float(H);
    float v = 1.0f - P.params2.x * dot(uv, uv);
    c *= max(v, 0.0f);
    float3 m = aces_fitted(c);
    // Triangular dither of one 8-bit step hides banding in dark gradients.
    uint h = pcg_hash(i * 3u + 17u);
    float d = (float(h & 0xFFFFu) / 65535.0f + float(h >> 16u) / 65535.0f - 1.0f) / 255.0f;
    float3 s = float3(srgb(m.x), srgb(m.y), srgb(m.z)) + d;
    s = clamp(s, 0.0f, 1.0f);
    out[i] = uchar4(uchar(s.x * 255.0f + 0.5f), uchar(s.y * 255.0f + 0.5f), uchar(s.z * 255.0f + 0.5f), 255);
}
"""#
}
