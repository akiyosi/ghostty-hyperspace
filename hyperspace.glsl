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
const float WARP_INTERVAL = 16.0; // cruise seconds between warps (0 = never warp)
const float ENTRY_DUR     = 4.0;  // warp entry length (tails grow outward)
const float EXIT_DUR      = 4.0;  // warp exit length (lines converge)
// derived timeline (do not edit)
const float CYCLE  = WARP_INTERVAL + ENTRY_DUR + EXIT_DUR;
const float JUMP_T = WARP_INTERVAL;                 // warp begins
const float PEAK_T = WARP_INTERVAL + ENTRY_DUR;     // field swap flash
const float EXIT_T = CYCLE;                         // arrival (cycle end)

const float EMAX      = 1.1;    // entry stretch: how far each line extends outward
const float CONV      = 0.96;   // exit stretch: inward tails reach near the centre (<1)
const float SLOW_T    = 0.7;    // seconds the tail spends slowly starting to extend
const float SLOW_FRAC = 0.08;   // small length reached by the end of that slow onset
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

// ---- realism: colour spread, rare close stars, galactic plane -----
const float NEAR_RARE = 0.991;  // rarity threshold for a "nearby" brighter star
                                // (higher = rarer; ~0.9% of cells above 0.991)
const float NEAR_GLOW = 0.12;   // soft halo of those rare stars (NO spikes -- that
                                // stays exclusive to the hero "dazzling" suns)
const float CROSS_RATE= 0.9999; // step threshold -> ~0.01% of points carry a small
                                // diffraction cross (very rare special star)
const float CROSS_AMP = 0.22;   // brightness of that cross
const float CROSS_LEN = 0.025;  // its arm length (screen heights)
const float GAL_WIDTH = 0.22;   // thickness of the galactic band (screen heights)
const float GAL_DENS  = 3.5;    // extra star density along the galactic plane
const float GAL_GLOW  = 1.4;    // brightness of the band's diffuse (unresolved) glow

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

// ---- value-noise fbm (galactic dust) ------------------------
float vnoise(vec2 p){
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash11(dot(i, vec2(1.0, 57.0)));
    float b = hash11(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0)));
    float c = hash11(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0)));
    float d = hash11(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0)));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p){
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++){ s += a * vnoise(p); p *= 2.03; a *= 0.5; }
    return s;
}

// ---- blackbody colour (Planckian locus, ~1500..30000 K) -----
vec3 blackbody(float K){
    K = clamp(K, 1500.0, 30000.0);
    float t = K / 100.0;
    float r, g, b;
    if (t <= 66.0) r = 1.0;
    else           r = clamp(1.292 * pow(t - 60.0, -0.1332), 0.0, 1.0);
    if (t <= 66.0) g = clamp(0.390 * log(t) - 0.634, 0.0, 1.0);
    else           g = clamp(1.129 * pow(t - 60.0, -0.0755), 0.0, 1.0);
    if (t >= 66.0) b = 1.0;
    else if (t <= 19.0) b = 0.0;
    else           b = clamp(0.543 * log(t - 10.0) - 1.196, 0.0, 1.0);
    return vec3(r, g, b);
}

// ---- realistic stellar colour from a 0..1 seed --------------
//  Real populations skew COOL (many orange/red dwarfs, fewer white, rare
//  blue). Map the hash through a cool-weighted temperature, take the true
//  blackbody colour, and desaturate a little (as the eye sees faint stars).
vec3 starColor(float h){
    float temp = mix(2900.0, 22000.0, pow(h, 2.4));   // cool-weighted; rare hot/blue
    vec3  c = blackbody(temp);
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    return mix(vec3(luma), c, 0.82);                   // slight desaturation
}

// ---- cheap cell starfield (uniform, any density, O(1)) ------
//  rdir : radial direction (from screen centre); el : radial stretch.
//  A point is thin across (STAR_PX) and stretched ALONG the radial by
//  `el` during warp, so each motion-blur sample is a short dash that
//  joins the next -> continuous thin starlines with few samples.
vec3 cellLayer(vec2 c, float scale, float seed, float pw, float gain,
               vec2 rdir, float el, float zk, float galDen,
               mat2 invSR, float crossAmt){
    vec2 g  = c * scale;
    vec2 id = floor(g);
    vec2 f  = fract(g) - 0.5;
    // per-cell attributes from a good 2D hash with INDEPENDENT offsets --
    // never hash11(dot(id,k)) (its linear argument makes diagonal banding and
    // correlates the tiers); this keeps brightness/colour/type uncorrelated
    // and the placement looking random, not patterned.
    float br = pow(hash22(id + vec2(seed +  0.5, seed * 1.3 + 2.1)).x, pw);
    br *= galDen;                                     // denser along the galaxy
    // special stars (near-glow / cross) ONLY on coarse octaves, whose cells are
    // big enough to hold their wide effect; otherwise the halo/cross would be
    // clipped at the cell edge (only this cell is sampled).
    float coarse = step(scale, 45.0);
    float near   = coarse * smoothstep(NEAR_RARE, 1.0,
                           hash22(id + vec2(seed + 11.0, seed * 1.1 + 4.7)).x);
    float crossH = coarse * step(CROSS_RATE,
                           hash22(id + vec2(seed + 41.0, seed * 1.7 + 3.3)).y);
    float special = max(near, crossH);
    // pull SPECIAL stars toward the cell centre so their wide halo/cross stays
    // inside the cell (no cut-off edges); ordinary points keep full jitter.
    vec2  off = (hash22(id + vec2(seed + 5.0, seed * 0.7 + 9.3)) - 0.5)
                * 0.9 * (1.0 - special * 0.85);
    float size = 1.0 + near * 0.45;
    br *= 1.0 + near * 1.3;
    vec2  rel = f - off;
    float al  = dot(rel, rdir);                       // along the radial
    float pe  = dot(rel, vec2(-rdir.y, rdir.x));      // perpendicular
    float rad = STAR_PX * scale / zk * size;           // /zk -> CONSTANT screen width
    float d2  = sq(pe / max(rad, 1e-4)) + sq(al / max(rad * el, 1e-4));
    float core = exp(-d2);
    float hd2  = sq(pe / max(rad * 6.0, 1e-4)) + sq(al / max(rad * 6.0 * el, 1e-4));
    float halo = near * NEAR_GLOW * exp(-hd2);         // gentle glow for near stars
    float ch  = hash22(id + vec2(seed + 23.0, seed * 0.9 + 7.1)).x;
    vec3  col = starColor(ch) * br * (core + halo) * gain;

    // the very rare cross star (flag computed above): screen-axis aligned
    // (undo the field rotation) and only at rest (crossAmt 0 during warp).
    if (crossAmt > 0.001 && crossH > 0.0){
        vec2  so  = invSR * (rel / scale);             // star->pixel, screen axes
        float len = CROSS_LEN * crossAmt;
        float sx  = exp(-sq(so.y) / sq(0.0014)) * exp(-abs(so.x) / max(len, 1e-4));
        float sy  = exp(-sq(so.x) / sq(0.0014)) * exp(-abs(so.y) / max(len, 1e-4));
        col += starColor(ch) * br * (sx + sy) * CROSS_AMP * crossAmt * gain;
    }
    return col;
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
    vec2 jj = (hash22(hid + vec2(seed + 5.0, seed * 0.7 + 9.3)) - 0.5) * 0.7;
    vec2 f  = (fract(lp) - 0.5) - jj;
    float br = pow(hash22(hid + vec2(seed + 0.5, seed * 1.3 + 2.1)).x, pw);
    float ch = hash22(hid + vec2(seed + 23.0, seed * 0.9 + 7.1)).x;
    return starColor(ch) * br * exp(-dot(f, f) / sq(0.34)) * gain;
}

vec3 fieldStars(vec2 c, float seed, vec2 rdir, float el, float zk, float warp,
                mat2 invSR, float crossAmt){
    // galactic plane: a band across the sky (orientation/offset per location)
    // along which stars are markedly denser -- the Milky-Way disk edge-on.
    float ga   = hash11(seed * 0.531 + 4.0) * 3.14159;
    vec2  gN   = vec2(-sin(ga), cos(ga));            // band normal
    float gOff = (hash11(seed * 0.917 + 8.0) - 0.5) * 0.7;
    float bd   = dot(c, gN) - gOff;                   // distance from band centre
    float band = exp(-bd * bd / (GAL_WIDTH * GAL_WIDTH));
    float galOn = step(0.5, hash11(seed * 0.331 + 2.0)); // ~50%: this region has a disk
    float galDen = 1.0 + GAL_DENS * band * galOn;     // density bias toward the disk

    // distant suns -- FIXED positions. During warp they stretch in place
    // (the radial sampling does it); they never fly past or vanish.
    vec3 col = cellLayer(c,  7.0 * DENS, seed + 1.0, 2.4, 0.65, rdir, el, zk, galDen, invSR, crossAmt)
             + cellLayer(c, 15.0 * DENS, seed + 2.0, 3.2, 0.45, rdir, el, zk, galDen, invSR, crossAmt)
             + cellLayer(c, 31.0 * DENS, seed + 3.0, 4.0, 0.33, rdir, el, zk, galDen, invSR, crossAmt);
    // fainter, more numerous suns, revealed by the jump's light-stretch
    float rev = mix(REVEAL, 1.0, warp);
    col += ( cellLayer(c, 55.0, seed + 11.0, 3.0, 0.50, rdir, el, zk, galDen, invSR, crossAmt)
           + cellLayer(c,105.0, seed + 12.0, 3.6, 0.40, rdir, el, zk, galDen, invSR, crossAmt)
           + cellLayer(c,200.0, seed + 13.0, 4.0, 0.32, rdir, el, zk, galDen, invSR, crossAmt) ) * rev;
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
               mat2 invSR, mat2 SR, float spikeGrow, float still, float aspect){
    vec3 col = vec3(0.0);
    // count: mostly none or a single bright sun; two is rare, three never
    float hn = hash11(seed * 1.93 + 7.7);
    int n = (hn < 0.62) ? 0
          : (hn < 0.98) ? 1 : 2;
    for (int i = 0; i < HERO_MAX; i++){
        if (i >= n) break;
        float fi  = float(i) + 1.0;
        // pick an ON-SCREEN position (screen/ps coords), randomised per sun and
        // per jump, then rotate into the field's (pr) space. Keeping it on
        // screen is why a present sun is actually visible.
        vec2  hpos = (hash22(vec2(fi * 37.1 + seed * 1.7,
                                  seed * 0.97 + fi * 13.3)) - 0.5)
                     * vec2(aspect, 1.0) * 0.92;
        vec2  P   = SR * hpos;
        float mag = mix(0.6, 1.0, hash11(fi * 6.6 + seed * 2.1));
        vec3  c   = starColor(hash11(fi * 7.1 + seed));

        // gentle fade if right at the screen edge (so a cross arm never peeks
        // in from just outside)
        float ax   = aspect * 0.5;
        float vis  = (1.0 - smoothstep(ax - 0.05, ax + 0.02, abs(hpos.x)))
                   * (1.0 - smoothstep(0.45,     0.52,      abs(hpos.y)));

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
        col += (vec3(core) + c * (halo + spikes)) * mag * still * vis;
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
    // WARP_INTERVAL == 0 -> never warp: a permanently static starfield
    if (WARP_INTERVAL <= 0.0){
        zLo = 1.0; zHi = 1.0; warp = 0.0; flash = 0.0; coreGlow = 0.0;
        shake = vec2(0.0); return;
    }
    float ph = mod(t, CYCLE);

    if (ph < JUMP_T || ph >= EXIT_T){
        zLo = 1.0; zHi = 1.0; warp = 0.0;                 // cruise: points at Q
    } else if (ph < PEAK_T){
        // tails grow OUTWARD from the star: the first SLOW_T seconds it only
        // creeps out slowly (the gentle "starting to extend"), then it grows
        // the rest of the way to full length by the peak. Linear segments so
        // the slow onset is steady (no extra slow patch afterwards).
        float te    = ph - JUMP_T;                        // seconds into entry
        float entry = PEAK_T - JUMP_T;
        float g = (te < SLOW_T)
                ? (te / SLOW_T) * SLOW_FRAC
                : SLOW_FRAC + (1.0 - SLOW_FRAC) * ((te - SLOW_T) / (entry - SLOW_T));
        zLo = 1.0;
        zHi = 1.0 + EMAX * g;
        warp = g;
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
    // the destination field is what decelerates into place). A per-LAUNCH
    // offset comes from the launch wall-time = floor(iDate.w - iTime): both
    // advance together so their difference is the (constant) start second --
    // FLOORED so sub-frame clock jitter can't change it (no flicker), yet it
    // differs between launches so even the first sky is random.
    float launch = hash11(floor(iDate.w - iTime) + 0.5) * 977.0;
    float seed = (WARP_INTERVAL <= 0.0)
               ? launch                                   // never warp -> one fixed sky
               : mod(floor((iTime - PEAK_T) / CYCLE) * 131.7 + launch, 977.0);

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

    // spike timing: crosses (hero + the ~0.01% field stars) appear only at rest
    // and EXTEND after arrival; crossAmt = still * spikeGrow (0 during warp).
    float spikeGrow = 1.0, still = 1.0;
    if (WARP_INTERVAL > 0.0){
        float phc = mod(iTime, CYCLE);
        float clock = (phc >= EXIT_T) ? (phc - EXIT_T)
                    : (phc < JUMP_T)  ? (phc + CYCLE - EXIT_T)
                                      : 0.0;
        spikeGrow = smoothstep(0.0, SPIKE_TIME, clock);
        still = (phc < JUMP_T || phc >= EXIT_T) ? 1.0
              : (phc < PEAK_T) ? 0.0
              : smoothstep(EXIT_T - 0.6, EXIT_T, phc);
    }
    float crossAmt = still * spikeGrow;            // = 1 (fully shown) when warp off

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
        stars = max(stars, fieldStars(q, seed, rdir, el, zk, warp, invSR, crossAmt));
    }
    stars *= STAR_GAIN;

    stars += heroStars(pr, zLo, zHi, warp, seed, invSR, SR, spikeGrow, still, R.x / R.y);

    // brighten hard toward the climax so the streaks blaze & the screen fills
    stars *= 1.0 + warp * WARP_GLOW;
    stars *= mix(vec3(1.0), vec3(0.80, 0.88, 1.15), warp * 0.5);

    // ---- assemble the frame ---------------------------------
    vec3 space = vec3(0.004, 0.006, 0.012);
    space += stars;

    // galactic band: faint diffuse glow of unresolved stars + dust lanes,
    // along the same plane the field is densified on. A cruise feature
    // (fades during the jump). Orientation per location (seed).
    float gga  = hash11(seed * 0.531 + 4.0) * 3.14159;
    vec2  ggN  = vec2(-sin(gga), cos(gga));
    float ggO  = (hash11(seed * 0.917 + 8.0) - 0.5) * 0.7;
    float gbd  = dot(pr, ggN) - ggO;
    float gband= exp(-gbd * gbd / sq(GAL_WIDTH * 1.6));
    float dust = fbm(pr * 3.0 + seed);
    float lane = smoothstep(0.35, 0.70, fbm(pr * 7.0 + seed + 11.0));
    vec3  gcol = mix(vec3(0.05, 0.05, 0.07), vec3(0.11, 0.10, 0.10), dust);
    float galOn = step(0.5, hash11(seed * 0.331 + 2.0)); // same flag as fieldStars
    space += gcol * gband * GAL_GLOW * (1.0 - 0.6 * lane) * (1.0 - 0.85 * warp) * galOn;

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
