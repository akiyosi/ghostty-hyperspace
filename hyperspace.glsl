// =============================================================
//  hyperspace.glsl  —  custom shader for Ghostty / Zonvie
//
//  Normal space, then a periodic Star Wars lightspeed jump.
//
//  Choreography
//    1. cruise   : a still, uniform starfield. A few stars blaze far
//                  brighter than the rest -- the nearby suns.
//    2. entry    : the stars on screen begin to stretch into tails.
//    3. build    : tails lengthen; more and more stars stream in.
//    4. accelerate: the field flies forward faster and faster.
//    5. climax   : radial speed-lines fill the screen, blinding white.
//    6. arrival  : a flash, and a DIFFERENT starfield (new suns).
//
//  Performance: the streaks are a radial ZOOM-BLUR of a cheap cell
//  starfield -- cost depends on the blur sample count K, NOT on the
//  number of stars, so density is essentially free. In cruise K=1, so
//  the blur collapses to the plain static field (and idle frames are
//  cheap). The same field is shown throughout, so the very stars you
//  see in cruise are the ones that stretch.
//
//  Setup
//    Ghostty (~/.config/ghostty/config):
//      custom-shader = /abs/path/hyperspace.glsl
//      custom-shader-animation = true
//    Zonvie (config.toml):
//      [shaders]
//      paths = ["/abs/path/hyperspace.glsl"]      (absolute path!)
//  Opaque-safe compositing (luminance key) -- no transparency needed.
// =============================================================

// ---------------- tunables -----------------------------------
const float CYCLE     = 24.0;   // seconds between jumps
const float JUMP_T    = 9.0;    // warp begins (tails grow outward)
const float PEAK_T    = 16.0;   // field swap flash (~7s entry)
const float EXIT_T    = 23.0;   // arrival: dense centre lines converge (~7s)

const float EMAX      = 1.1;    // entry stretch: how far each line extends outward
const float CONV      = 0.96;   // exit stretch: inward tails reach near the centre (<1)
const float ACCEL     = 1.7;    // >1 accelerates; the jump keeps streaming to the peak
const int   KMAX      = 20;     // motion-blur samples during warp
const float EL        = 18.0;   // radial stretch of each sample (joins streaks)

const float STAR_GAIN = 1.45;   // overall brightness
const float WARP_GLOW = 5.0;    // extra streak brightness during the jump
const float STAR_PX   = 0.0007; // star radius in screen heights (thin points/lines)
const float DENS      = 1.0;    // cruise field density (count ~ DENS^2)
const float REVEAL    = 0.10;   // how visible the faint suns are before the jump
const float SPIKE_TIME= 2.2;    // seconds for the bright suns' spikes to extend

const int   HERO_MAX  = 3;      // up to this many extra-bright nearby suns
const float HERO_GAIN = 2.3;    // their brightness

// ---- compositing (opaque-safe: Ghostty AND Zonvie) ----------
#define BLEND_ALPHA 0           // 1: alpha blend (transparent Ghostty only)
const float BG_LEVEL = 0.12;    // theme background brightness (raise if needed)
const float BG_SOFT  = 0.10;    // glyph-edge softness of the key
// -------------------------------------------------------------

float sq(float x){ return x * x; }

// ---- hashes -------------------------------------------------
float hash11(float p){
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}
vec2 hash22(vec2 p){
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ---- stellar colour from a 0..1 seed (white-biased) ---------
vec3 starColor(float h){
    vec3 warm = vec3(1.00, 0.78, 0.55);  // K / M  orange-red
    vec3 white= vec3(1.00, 0.97, 0.92);  // G / F  sun-white
    vec3 blue = vec3(0.74, 0.83, 1.00);  // A / B  blue-white
    return h < 0.5 ? mix(warm, white, h * 2.0)
                   : mix(white, blue, (h - 0.5) * 2.0);
}

// ---- cheap cell starfield (uniform, any density, O(1)) ------
//  rdir : radial direction (from screen centre); el : radial stretch.
//  A point is thin across (STAR_PX) and stretched ALONG the radial by
//  `el` during warp, so each motion-blur sample is a short dash that
//  joins the next -> continuous thin starlines with few samples.
vec3 cellLayer(vec2 c, float scale, float seed, float pw, float gain,
               vec2 rdir, float el, float zk){
    vec2 g  = c * scale;
    vec2 id = floor(g);
    vec2 f  = fract(g) - 0.5;
    float br = pow(hash11(dot(id, vec2(127.1, 311.7)) + seed), pw);
    vec2  off = (hash22(id + seed) - 0.5) * 0.7;
    vec2  rel = f - off;
    float al  = dot(rel, rdir);                       // along the radial
    float pe  = dot(rel, vec2(-rdir.y, rdir.x));      // perpendicular
    float rad = STAR_PX * scale / zk;                  // /zk -> CONSTANT screen width
    float d2  = sq(pe / max(rad, 1e-4)) + sq(al / max(rad * el, 1e-4));
    float ch  = hash11(dot(id, vec2(57.0, 113.0)) + seed);
    return starColor(ch) * br * exp(-d2) * gain;
}
// log-polar star layer: stars on an (angle, log radius) grid, so the
// on-screen density rises naturally toward the centre (the 1/r^2 of looking
// down the travel direction). Real hashed stars, not a boost. The radial
// tail comes from the zoom sampling, as for the Cartesian layers.
vec3 polarLayer(vec2 q, float angN, float radS, float seed, float pw, float gain){
    float rr = length(q);
    if (rr < 1e-4) return vec3(0.0);
    float a  = atan(q.y, q.x);
    vec2 lp = vec2(a * (angN * 0.1591549), log(rr) * radS);
    vec2 id = floor(lp);
    float aw = mod(id.x, angN);                       // seamless angular wrap
    vec2 hid = vec2(aw, id.y);
    vec2 jj = (hash22(hid + seed) - 0.5) * 0.7;
    vec2 f  = (fract(lp) - 0.5) - jj;
    float br = pow(hash11(dot(hid, vec2(41.3, 289.1)) + seed), pw);
    float ch = hash11(dot(hid, vec2(73.0, 29.0)) + seed);
    return starColor(ch) * br * exp(-dot(f, f) / sq(0.34)) * gain;
}

vec3 fieldStars(vec2 c, float seed, vec2 rdir, float el, float zk, float warp){
    // distant suns -- FIXED positions. During warp they stretch in place
    // (the radial sampling does it); they never fly past or vanish.
    vec3 col = cellLayer(c,  7.0 * DENS, seed + 1.0, 2.4, 0.65, rdir, el, zk)
             + cellLayer(c, 15.0 * DENS, seed + 2.0, 3.2, 0.45, rdir, el, zk)
             + cellLayer(c, 31.0 * DENS, seed + 3.0, 4.0, 0.33, rdir, el, zk);
    // fainter, more numerous suns, revealed by the jump's light-stretch
    float rev = mix(REVEAL, 1.0, warp);
    col += ( cellLayer(c, 55.0, seed + 11.0, 3.0, 0.50, rdir, el, zk)
           + cellLayer(c,105.0, seed + 12.0, 3.6, 0.40, rdir, el, zk)
           + cellLayer(c,200.0, seed + 13.0, 4.0, 0.32, rdir, el, zk) ) * rev;
    // LATE WARP: a perspective (1/r^2) field packs dense stars + tails into
    // the centre. Absent in cruise (no centre haze); ramps in for the finale.
    float late = smoothstep(0.25, 0.75, warp);
    if (late > 0.001){
        col += ( polarLayer(c, 200.0, 26.0, seed + 21.0, 2.4, 0.85)
               + polarLayer(c, 200.0, 40.0, seed + 22.0, 2.8, 0.60) ) * late;
    }
    return col;
}

// ---- a few extra-bright nearby suns, rendered like real stars
//  Cruise: hot white core + airy glow + 4-point diffraction spikes,
//  tinted by colour. Warp: it streaks with the field (no spikes).
vec3 heroStars(vec2 p, float zLo, float zHi, float warp, float seed,
               mat2 invSR, float spikeGrow, float still){
    vec3 col = vec3(0.0);
    int n = 1 + int(hash11(seed * 0.37 + 5.0) * float(HERO_MAX));
    for (int i = 0; i < HERO_MAX; i++){
        if (i >= n) break;
        float fi  = float(i) + 1.0;
        vec2  P   = (hash22(vec2(fi * 9.13, seed + 50.0)) - 0.5) * 1.7;
        float mag = mix(0.6, 1.0, hash11(fi * 6.6 + seed));
        vec3  c   = starColor(hash11(fi * 7.1 + seed));

        // warp: the streak segment [P*zLo, P*zHi], same as the field
        vec2  head = P * zHi, tail = P * zLo;
        vec2  ab = head - tail, ap = p - tail;
        float t  = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-9), 0.0, 1.0);
        vec2  e  = ap - ab * t;
        col += c * mag * exp(-dot(e, e) / sq(0.0011)) * (1.0 - still); // uniform, no fade

        // cruise: a realistic bright star at its resting position
        vec2  d  = p - P;
        float r2 = dot(d, d);
        float core  = exp(-r2 / sq(0.0026));
        float halo  = exp(-r2 / sq(0.020)) * 0.18;
        // diffraction spikes are a CAMERA artifact -> keep them aligned to
        // the screen axes (undo the per-jump field rotation). Their length
        // EXTENDS gradually after arrival (spikeGrow 0 -> 1).
        vec2  ds = invSR * d;
        float sl = 0.055 * spikeGrow;                      // spike reach grows in
        float sx = exp(-sq(ds.y) / sq(0.0015)) * exp(-abs(ds.x) / max(sl, 1e-4));
        float sy = exp(-sq(ds.x) / sq(0.0015)) * exp(-abs(ds.y) / max(sl, 1e-4));
        float spikes = (sx + sy) * 0.45 * spikeGrow;
        col += (vec3(core) + c * (halo + spikes)) * mag * still;
    }
    return col * HERO_GAIN;
}

// ---- jump state machine -------------------------------------
//  A streak is the screen segment [Q*zLo, Q*zHi] for a star at rest Q.
//   * entry : zLo=1 (star is the INNER end), zHi grows -> line extends
//             OUTWARD from the star.
//   * peak  : FLASH + reseed -- swap the entry field for the destination.
//   * exit  : zHi=1 (the star sits at its rest Q, the OUTER end of an
//             inward tail), zLo rises 1-CONV -> 1 so the tail retracts and
//             the star CONVERGES onto Q. Since cruise is also zk=1 -> Q,
//             the convergence target EXACTLY matches the new starfield
//             (no misalignment, no zoom reset).
void warpState(float t, out float zLo, out float zHi, out float warp,
               out float flash, out float coreGlow, out vec2 shake){
    float ph = mod(t, CYCLE);

    if (ph < JUMP_T || ph >= EXIT_T){
        zLo = 1.0; zHi = 1.0; warp = 0.0;                 // cruise: points at Q
    } else if (ph < PEAK_T){
        float accel = (ph - JUMP_T) / (PEAK_T - JUMP_T);
        zLo = 1.0;
        zHi = 1.0 + EMAX * pow(accel, ACCEL * 0.7);       // grow OUTWARD from star
        warp = accel;
    } else {
        float d = smoothstep(0.0, 1.0, (ph - PEAK_T) / (EXIT_T - PEAK_T));
        zLo = 1.0 - CONV * (1.0 - d);                     // inward tail retracts...
        zHi = 1.0;                                        // ...to the star at Q
        warp = 1.0 - d;
    }

    flash = 2.2 * exp(-sq((ph - PEAK_T) / 0.22));         // flash at the field swap
    coreGlow = warp * smoothstep(0.5, 1.0, warp);         // bright centre near peak
    float chg = (ph > JUMP_T && ph < PEAK_T) ? warp : 0.0;
    shake = chg * 0.0035 * vec2(sin(t * 47.0), cos(t * 39.0));
}

// =============================================================
void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 R  = iResolution.xy;
    vec2 uv = fragCoord / R;
    vec2 p  = (fragCoord - 0.5 * R) / R.y;   // centred, aspect-correct

    float zLo, zHi, warp, flash, coreGlow; vec2 shake;
    warpState(iTime, zLo, zHi, warp, flash, coreGlow, shake);

    vec2  ps = p + shake;
    float r  = length(ps);

    // new region after each jump (seed advances at the peak flash/swap, so
    // the destination field is what decelerates into place)
    float seed = mod(floor((iTime - PEAK_T) / CYCLE) * 131.7, 977.0);

    // ---- radial zoom-blur: cost is K, not the star count --------
    //  q = ps/zk samples the field at receding "previous" positions;
    //  accumulating them smears each star into a radial streak whose
    //  length grows with `streak` and whose stars stream outward as
    //  `fly` grows. At cruise (fly=streak=0, K=1) it is the plain field.
    // rotate the whole field by a per-jump angle so each destination is
    // visibly a DIFFERENT sky (rotation about the centre keeps streaks
    // radial). The bright suns ride along, so they are never fixed.
    float sa = seed * 0.613;
    mat2  SR = mat2(cos(sa), -sin(sa), sin(sa), cos(sa));
    mat2  invSR = mat2(cos(sa), sin(sa), -sin(sa), cos(sa));  // undo rotation (screen axes)
    vec2  pr = SR * ps;

    bool  warping = (zHi - zLo) > 0.001;
    int   K = warping ? KMAX : 1;
    vec2  rdir = normalize(pr + vec2(1e-5));         // radial direction from centre
    float el   = 1.0 + warp * EL;                    // dash stretch during warp
    float jit  = hash11(dot(fragCoord, vec2(0.0073, 0.0131)));
    vec3  stars = vec3(0.0);
    for (int k = 0; k < KMAX; k++){
        if (k >= K) break;
        float tt = (float(k) + jit) / float(K);
        float zk = mix(zLo, zHi, tt);                // segment [Q*zLo, Q*zHi]
        vec2  q  = pr / zk;
        // MAX (not sum/K): every point on the streak keeps the star's FULL
        // brightness -- so even the short early streaks read brightly.
        stars = max(stars, fieldStars(q, seed, rdir, el, zk, warp));
    }
    stars *= STAR_GAIN;

    // the bright suns' diffraction spikes EXTEND only AFTER arrival: zero
    // during the whole jump [JUMP_T, EXIT_T], then grow through cruise
    // (continuous across the cycle wrap).
    float phc = mod(iTime, CYCLE);
    float clock = (phc >= EXIT_T) ? (phc - EXIT_T)
                : (phc < JUMP_T)  ? (phc + CYCLE - EXIT_T)
                                  : 0.0;                  // jump in progress: no spikes
    float spikeGrow = smoothstep(0.0, SPIKE_TIME, clock);
    // hero realistic star: streaks during the jump, then fades in smoothly
    // as the streak converges to its point near arrival
    float still = (phc < JUMP_T || phc >= EXIT_T) ? 1.0
                : (phc < PEAK_T) ? 0.0
                : smoothstep(EXIT_T - 0.6, EXIT_T, phc);
    stars += heroStars(pr, zLo, zHi, warp, seed, invSR, spikeGrow, still);

    // brighten hard toward the climax so the streaks blaze & the screen fills
    stars *= 1.0 + warp * WARP_GLOW;
    stars *= mix(vec3(1.0), vec3(0.80, 0.88, 1.15), warp * 0.5);

    // ---- assemble the frame ---------------------------------
    vec3 space = vec3(0.004, 0.006, 0.012);
    space += stars;
    space += vec3(0.55, 0.7, 1.0) * coreGlow * exp(-r * r * 3.0) * 0.7;  // climax core
    space += vec3(0.90, 0.95, 1.0) * clamp(flash, 0.0, 2.6);            // jump flash

    float vig = smoothstep(1.4, 0.25, r);
    space *= mix(0.65, 1.0, vig);
    space  = 1.0 - exp(-space * 1.9);        // soft filmic exposure
    space  = pow(space, vec3(0.95));

    // ---- composite the terminal on top ----------------------
    vec4 term = texture(iChannel0, uv);
#if BLEND_ALPHA
    vec3 outc = term.rgb + space * (1.0 - term.a);
#else
    float lum      = max(max(term.r, term.g), term.b);
    float textMask = smoothstep(BG_LEVEL, BG_LEVEL + BG_SOFT, lum);
    vec3  outc     = mix(space, term.rgb, textMask);
#endif

    fragColor = vec4(outc, 1.0);
}
