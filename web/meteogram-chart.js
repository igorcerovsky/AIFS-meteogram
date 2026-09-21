/**
 * Interactive Client-Side Meteogram Canvas Chart Engine
 * Inspired by SHMÚ EPSGRAM & ECMWF AIFS ensemble forecasts.
 * 
 * Features:
 * - 5 synchronized panels (Temperature, Precipitation/Snow, Cloud Layers, Wind, MSLP Pressure)
 * - HiDPI / Retina canvas rendering with sub-pixel crispness
 * - Synchronized vertical crosshair tracking across all panels
 * - Floating Glassmorphism HUD inspection tooltip showing exact values
 * - Real-time client-side astronomical ephemeris (Sun/Moon altitude curves, phases)
 * - Instant timezone (Local vs UTC) and language (EN vs SK) switching without refetch
 * - Direct Open-Meteo API client for zero-backend operation on GitHub Pages
 */

const METEO_TRANSLATIONS = {
  en: {
    title: "ECMWF AIFS Meteogram",
    subtitle: "Ensemble Forecast (SHMÚ EPSGRAM Style)",
    temp: "2m Temperature [°C]",
    precip: "Precipitation & Snowfall [mm / 6h]",
    clouds: "Cloud Cover [%]",
    wind: "10m Wind Speed [m/s] & Direction",
    pressure: "Mean Sea Level Pressure [hPa]",
    sun_alt: "Sun altitude [°]",
    moon_alt: "Moon altitude [°]",
    total_clouds: "Total",
    high_clouds: "High (cirrus)",
    mid_clouds: "Medium (alto)",
    low_clouds: "Low (stratus)",
    median: "Median",
    spread_50: "50% (Q25-Q75)",
    spread_100: "Min - Max member",
    freezing_line: "0 °C freezing",
    rain: "Rain",
    snow: "Snow",
    daily_sum: "Daily sum",
    wind_calm: "Calm",
    wind_light: "Light breeze",
    wind_moderate: "Moderate breeze",
    wind_strong: "Strong breeze / Gale",
    curve_thickness: "Curve thickness",
    local_time: "Local Time",
    utc_time: "UTC",
    above_horizon: "Daylight / Above horizon",
    below_horizon: "Night / Below horizon",
    moon_phase: "Moon phase",
    illum: "illumination",
    sunrise: "Sunrise",
    sunset: "Sunset",
    moonrise: "Moonrise",
    moonset: "Moonset",
    days_short: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    days_full: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
    months_short: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
  },
  sk: {
    title: "ECMWF AIFS Meteogram",
    subtitle: "Ensemblová predpoveď (štýl SHMÚ EPSGRAM)",
    temp: "Teplota vzduchu 2 m [°C]",
    precip: "Zrážky a sneženie [mm / 6h]",
    clouds: "Oblačnosť [%]",
    wind: "Rýchlosť [m/s] a smer vetra 10 m",
    pressure: "Tlak vzduchu prepočítaný na hladinu mora [hPa]",
    sun_alt: "Výška slnka [°]",
    moon_alt: "Výška mesiaca [°]",
    total_clouds: "Celková",
    high_clouds: "Vysoká (cirrus)",
    mid_clouds: "Stredná (alto)",
    low_clouds: "Nízka (stratus)",
    median: "Medián",
    spread_50: "50% členov (Q25-Q75)",
    spread_100: "Rozpätie všetkých členov (Min - Max)",
    freezing_line: "0 °C hladina mrazu",
    rain: "Dážď",
    snow: "Sneh",
    daily_sum: "Denný úhrn",
    wind_calm: "Bezvetrie",
    wind_light: "Mierny vietor",
    wind_moderate: "Čerstvý vietor",
    wind_strong: "Silný vietor / Víchrica",
    curve_thickness: "Hrúbka krivky",
    local_time: "Miestny čas",
    utc_time: "UTC",
    above_horizon: "Deň / Nad obzorom",
    below_horizon: "Noc / Pod obzorom",
    moon_phase: "Fáza mesiaca",
    illum: "osvetlenie",
    sunrise: "Východ slnka",
    sunset: "Západ slnka",
    moonrise: "Východ mesiaca",
    moonset: "Západ mesiaca",
    days_short: ["Ne", "Po", "Ut", "St", "Št", "Pi", "So"],
    days_full: ["Nedeľa", "Pondelok", "Utorok", "Streda", "Štvrtok", "Piatok", "Sobota"],
    months_short: ["jan", "feb", "mar", "apr", "máj", "jún", "júl", "aug", "sep", "okt", "nov", "dec"],
  },
};

// Wind compass directions
const COMPASS_DIRS_EN = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
const COMPASS_DIRS_SK = ["S", "SSV", "SV", "VSV", "V", "VJV", "JV", "JJV", "J", "JJZ", "JZ", "ZJZ", "Z", "ZSZ", "SZ", "SSZ"];

function getCompassDir(degrees, lang = "en") {
  const dirs = lang === "sk" ? COMPASS_DIRS_SK : COMPASS_DIRS_EN;
  const idx = Math.round(((degrees % 360) + 360) % 360 / 22.5) % 16;
  return dirs[idx];
}

// Astronomical formulas (Solar & Lunar altitude)
function calculateSolarAltitude(dateUtc, lat, lon) {
  const t_epoch = dateUtc.getTime() / 1000.0;
  const d = (t_epoch - 946728000.0) / 86400.0;

  const g = ((357.529 + 0.98560028 * d) % 360.0 + 360.0) % 360.0;
  const g_rad = g * Math.PI / 180.0;
  const q = ((280.459 + 0.98564736 * d) % 360.0 + 360.0) % 360.0;
  const l_ecl = ((q + 1.915 * Math.sin(g_rad) + 0.020 * Math.sin(2 * g_rad)) % 360.0 + 360.0) % 360.0;
  const l_rad = l_ecl * Math.PI / 180.0;

  const e = 23.439 - 0.00000036 * d;
  const e_rad = e * Math.PI / 180.0;

  const sin_dec = Math.sin(e_rad) * Math.sin(l_rad);
  const dec_rad = Math.asin(sin_dec);

  const y = Math.cos(e_rad) * Math.sin(l_rad);
  const x = Math.cos(l_rad);
  const ra_rad = Math.atan2(y, x);

  const gmst = ((280.46061837 + 360.98564736629 * d) % 360.0 + 360.0) % 360.0;
  const lst_rad = (((gmst + lon) % 360.0 + 360.0) % 360.0) * Math.PI / 180.0;
  const ha_rad = lst_rad - ra_rad;

  const lat_rad = lat * Math.PI / 180.0;
  const sin_alt = Math.sin(lat_rad) * Math.sin(dec_rad) + Math.cos(lat_rad) * Math.cos(dec_rad) * Math.cos(ha_rad);
  return Math.asin(Math.max(-1.0, Math.min(1.0, sin_alt))) * 180.0 / Math.PI;
}

function calculateSolarDeclinationAndEoT(dateUtc) {
  const t_epoch = dateUtc.getTime() / 1000.0;
  const d = (t_epoch - 946728000.0) / 86400.0;

  const g = ((357.529 + 0.98560028 * d) % 360.0 + 360.0) % 360.0;
  const g_rad = g * Math.PI / 180.0;
  const q = ((280.459 + 0.98564736 * d) % 360.0 + 360.0) % 360.0;
  const l_ecl = ((q + 1.915 * Math.sin(g_rad) + 0.020 * Math.sin(2 * g_rad)) % 360.0 + 360.0) % 360.0;
  const l_rad = l_ecl * Math.PI / 180.0;

  const e = 23.439 - 0.00000036 * d;
  const e_rad = e * Math.PI / 180.0;

  const sin_dec = Math.sin(e_rad) * Math.sin(l_rad);
  const dec_rad = Math.asin(sin_dec);
  const dec = dec_rad * 180.0 / Math.PI;

  const y = Math.cos(e_rad) * Math.sin(l_rad);
  const x = Math.cos(l_rad);
  const ra_rad = Math.atan2(y, x);

  const diff_deg = ((q - ra_rad * 180.0 / Math.PI) % 360.0 + 540.0) % 360.0 - 180.0;
  const eot = 4.0 * diff_deg; // Equation of Time in minutes

  return { dec, eot };
}

function getAnnualAnalemmaCurve(year = 2026) {
  const points = [];
  const start = new Date(Date.UTC(year, 0, 1, 12, 0, 0));
  for (let day = 0; day < 365; day++) {
    const d = new Date(start.getTime() + day * 86400000);
    points.push(calculateSolarDeclinationAndEoT(d));
  }
  return points;
}

function calculateLunarAltitude(dateUtc, lat, lon) {
  const t_epoch = dateUtc.getTime() / 1000.0;
  const d = (t_epoch - 946728000.0) / 86400.0;

  const l_moon = ((218.316 + 13.176396 * d) % 360.0 + 360.0) % 360.0;
  const m_moon = ((134.963 + 13.064993 * d) % 360.0 + 360.0) % 360.0;
  const f_moon = ((93.272 + 13.229350 * d) % 360.0 + 360.0) % 360.0;

  const m_rad = m_moon * Math.PI / 180.0;
  const f_rad = f_moon * Math.PI / 180.0;

  const lon_moon = l_moon + 6.289 * Math.sin(m_rad);
  const lat_moon = 5.128 * Math.sin(f_rad);

  const lon_rad = lon_moon * Math.PI / 180.0;
  const lat_rad_moon = lat_moon * Math.PI / 180.0;

  const e = 23.439 - 0.00000036 * d;
  const e_rad = e * Math.PI / 180.0;

  const sin_dec = (Math.sin(lat_rad_moon) * Math.cos(e_rad) +
                   Math.cos(lat_rad_moon) * Math.sin(e_rad) * Math.sin(lon_rad));
  const dec_rad = Math.asin(Math.max(-1.0, Math.min(1.0, sin_dec)));

  const y = (Math.sin(lon_rad) * Math.cos(e_rad) -
             Math.tan(lat_rad_moon) * Math.sin(e_rad));
  const x = Math.cos(lon_rad);
  const ra_rad = Math.atan2(y, x);

  const gmst = ((280.46061837 + 360.98564736629 * d) % 360.0 + 360.0) % 360.0;
  const lst_rad = (((gmst + lon) % 360.0 + 360.0) % 360.0) * Math.PI / 180.0;
  const ha_rad = lst_rad - ra_rad;

  const lat_rad = lat * Math.PI / 180.0;
  const sin_alt = (Math.sin(lat_rad) * Math.sin(dec_rad) +
                   Math.cos(lat_rad) * Math.cos(dec_rad) * Math.cos(ha_rad));
  return Math.asin(Math.max(-1.0, Math.min(1.0, sin_alt))) * 180.0 / Math.PI;
}

function getMoonPhaseName(phase, lang = "en") {
  const p = ((phase % 1.0) + 1.0) % 1.0;
  if (p < 0.03 || p >= 0.97) return lang === "sk" ? "Nov" : "New Moon";
  if (p < 0.22) return lang === "sk" ? "Dorastajúci kosák" : "Waxing Crescent";
  if (p < 0.28) return lang === "sk" ? "Prvá štvrť" : "First Quarter";
  if (p < 0.47) return lang === "sk" ? "Dorastajúci mesiac" : "Waxing Gibbous";
  if (p < 0.53) return lang === "sk" ? "Spln" : "Full Moon";
  if (p < 0.72) return lang === "sk" ? "Cúvajúci mesiac" : "Waning Gibbous";
  if (p < 0.78) return lang === "sk" ? "Posledná štvrť" : "Last Quarter";
  return lang === "sk" ? "Ubúdajúci kosák" : "Waning Crescent";
}


/**
 * MeteogramChart Class
 */
class MeteogramChart {
  constructor(container, options = {}) {
    this.container = typeof container === "string" ? document.querySelector(container) : container;
    if (!this.container) throw new Error("MeteogramChart: Container element not found");

    this.options = Object.assign({
      lang: "en",
      tz: "local",
      theme: "light",
      onHover: null,
    }, options);

    this.data = null;
    this.hoverIdx = null;
    this.hoverPos = null;
    this.analemmaCurve = getAnnualAnalemmaCurve();

    this._initDOM();
    this._initEvents();
  }

  _initDOM() {
    this.container.innerHTML = "";
    this.container.style.position = "relative";
    this.container.style.userSelect = "none";
    this.container.style.webkitUserSelect = "none";

    // Create Canvas with alpha: false to avoid black canvas Direct2D/WebRender bugs in Firefox on Windows
    this.canvas = document.createElement("canvas");
    this.canvas.style.display = "block";
    this.canvas.style.width = "100%";
    this.canvas.style.height = "auto";
    this.canvas.style.cursor = "crosshair";
    this.canvas.style.backgroundColor = "#ffffff";
    this.canvas.style.colorScheme = "light";
    this.container.style.backgroundColor = "#ffffff";
    this.container.style.colorScheme = "light";
    this.ctx = this.canvas.getContext("2d", { alpha: false, willReadFrequently: false }) || this.canvas.getContext("2d");
    this.container.appendChild(this.canvas);

    // Dedicated Fixed Interactive Info Pane (Mobile App Style)
    this._ensureHUDStyles();
    this.hud = document.getElementById("meteogram-hud-pane");
    if (!this.hud) {
      this.hud = document.createElement("div");
      this.hud.id = "meteogram-hud-pane";
      this.hud.className = "meteogram-hud-pane";
      if (this.container.parentNode) {
        this.container.parentNode.insertBefore(this.hud, this.container);
      } else {
        this.container.appendChild(this.hud);
      }
    }
    this._showIdleHUD();
  }

  _ensureHUDStyles() {
    if (document.getElementById("meteogram-chart-hud-styles")) return;
    const style = document.createElement("style");
    style.id = "meteogram-chart-hud-styles";
    style.textContent = `
      .meteogram-hud-pane {
        position: sticky;
        top: 10px;
        z-index: 45;
        background: var(--card-bg, #ffffff);
        border: 1px solid var(--card-border, #cbd5e1);
        border-radius: 10px;
        padding: 8px 16px;
        margin-bottom: 12px;
        box-shadow: var(--chart-box-shadow, 0 4px 18px rgba(0, 0, 0, 0.08));
        backdrop-filter: blur(12px);
        -webkit-backdrop-filter: blur(12px);
        min-height: 52px;
        display: flex;
        align-items: center;
        color: var(--text-main, #0f172a);
        font-family: 'Inter', system-ui, -apple-system, sans-serif;
      }
      [data-theme="dark"] .meteogram-hud-pane {
        background: rgba(22, 27, 34, 0.92);
        border-color: rgba(48, 54, 61, 0.8);
        box-shadow: 0 6px 24px rgba(0, 0, 0, 0.35);
        color: #f0f6fc;
      }
    `;
    document.head.appendChild(style);
  }

  _initEvents() {
    // Mouse & Pointer tracking
    this.canvas.addEventListener("mousemove", (e) => this._handlePointerMove(e));
    this.canvas.addEventListener("mouseleave", () => this._handlePointerLeave());
    this.canvas.addEventListener("pointermove", (e) => this._handlePointerMove(e));
    this.canvas.addEventListener("pointerleave", () => this._handlePointerLeave());
    this.canvas.addEventListener("pointerdown", (e) => this._handlePointerMove(e));
    this.canvas.addEventListener("click", (e) => this._handlePointerMove(e));

    // Touch tracking (mobile / tablet scrub)
    this.canvas.addEventListener("touchstart", (e) => {
      if (e.touches.length === 1) {
        this._handlePointerMove(e.touches[0]);
      }
    }, { passive: true });

    this.canvas.addEventListener("touchmove", (e) => {
      if (e.touches.length === 1) {
        this._handlePointerMove(e.touches[0]);
      }
    }, { passive: true });

    this.canvas.addEventListener("touchend", () => this._handlePointerLeave());

    // Window resize observer with debounced RAF to prevent layout thrashing / Firefox loops
    let resizeTimer = null;
    this.resizeObserver = new ResizeObserver(() => {
      if (!this.data) return;
      if (resizeTimer) cancelAnimationFrame(resizeTimer);
      resizeTimer = requestAnimationFrame(() => {
        const newWidth = Math.max(880, Math.floor(this.container.getBoundingClientRect().width));
        if (Math.abs(newWidth - (this.W || 0)) >= 2) {
          this.render();
        }
      });
    });
    this.resizeObserver.observe(this.container);
  }

  setData(payload) {
    this.data = payload;
    this._processData();
    this.render();
    if (this.hoverIdx !== null) {
      this._updateHUD(this.hoverIdx);
    } else {
      this._showIdleHUD();
    }
  }

  setOptions(newOptions) {
    Object.assign(this.options, newOptions);
    if (this.data) {
      this._processData();
      this.render();
      if (this.hoverIdx !== null) {
        this._updateHUD(this.hoverIdx);
      } else {
        this._showIdleHUD();
      }
    } else {
      this._showIdleHUD();
    }
  }

  _processData() {
    if (!this.data || !this.data.stats || !this.data.stats.times) return;

    const stats = this.data.stats;
    const timesRaw = stats.times;
    this.times = timesRaw.map(t => new Date(t));

    this.tStart = this.times[0].getTime();
    this.tEnd = this.times[this.times.length - 1].getTime();
    this.durationHours = (this.tEnd - this.tStart) / 3600000;

    // Daily precipitation accumulation aggregation
    this.dailyPrecipSums = {};
    const pMedian = stats.precipitation ? stats.precipitation.median : [];
    const pSnow = stats.snowfall ? stats.snowfall.median : [];

    for (let i = 0; i < this.times.length; i++) {
      const dt = this.times[i];
      const dKey = this._formatDateKey(dt);
      if (!this.dailyPrecipSums[dKey]) {
        this.dailyPrecipSums[dKey] = { rain: 0.0, snow: 0.0, startIdx: i, endIdx: i };
      }
      const rVal = (pMedian && pMedian[i] != null) ? pMedian[i] : 0.0;
      const sVal = (pSnow && pSnow[i] != null) ? pSnow[i] : 0.0;
      this.dailyPrecipSums[dKey].rain += rVal;
      this.dailyPrecipSums[dKey].snow += sVal;
      this.dailyPrecipSums[dKey].endIdx = i;
    }

    // Precalculate solar & lunar altitude timeseries for HUD
    const lat = (this.data.location && this.data.location.latitude) || 48.15;
    const lon = (this.data.location && this.data.location.longitude) || 17.10;
    this.sunAlts = this.times.map(t => calculateSolarAltitude(t, lat, lon));
    this.moonAlts = this.times.map(t => calculateLunarAltitude(t, lat, lon));

    // Calculate dense celestial passages starting and ending strictly at the bottom (horizon = 0.0°)
    const padMs = 18 * 3600 * 1000;
    const denseStart = this.tStart - padMs;
    const denseEnd = this.tEnd + padMs;
    const stepMs = 300 * 1000; // 5-minute steps for smooth trajectory arcs
    const nSteps = Math.floor((denseEnd - denseStart) / stepMs);

    const denseTimes = [];
    const denseSunAlts = [];
    const denseMoonAlts = [];

    for (let i = 0; i <= nSteps; i++) {
      const t = new Date(denseStart + i * stepMs);
      denseTimes.push(t);
      denseSunAlts.push(calculateSolarAltitude(t, lat, lon));
      denseMoonAlts.push(calculateLunarAltitude(t, lat, lon));
    }

    const extractPassages = (alts, isMoon = false) => {
      const passages = [];
      let inPass = false;
      let pStart = 0;

      for (let i = 0; i < alts.length; i++) {
        if (alts[i] >= 0.0 && !inPass) {
          inPass = true;
          pStart = i;
        } else if (alts[i] < 0.0 && inPass) {
          inPass = false;
          passages.push({ start: pStart, end: i });
        }
      }
      if (inPass) passages.push({ start: pStart, end: alts.length });

      const curves = [];
      const peaks = [];

      for (const pass of passages) {
        const segTimes = [];
        const segAlts = [];

        // Exact rising zero-crossing before pass.start (horizon = 0.0 -> bottom of graph)
        if (pass.start > 0 && alts[pass.start - 1] < 0.0) {
          const prevAlt = alts[pass.start - 1];
          const currAlt = alts[pass.start];
          const frac = (0.0 - prevAlt) / (currAlt - prevAlt);
          const tZero = denseTimes[pass.start - 1].getTime() + frac * (denseTimes[pass.start].getTime() - denseTimes[pass.start - 1].getTime());
          segTimes.push(tZero);
          segAlts.push(0.0); // Starts strictly at the bottom!
        }

        for (let i = pass.start; i < pass.end; i++) {
          segTimes.push(denseTimes[i].getTime());
          segAlts.push(alts[i]);
        }

        // Exact setting zero-crossing after pass.end - 1 (horizon = 0.0 -> bottom of graph)
        if (pass.end < alts.length && alts[pass.end] < 0.0) {
          const prevAlt = alts[pass.end - 1];
          const currAlt = alts[pass.end];
          const frac = (0.0 - prevAlt) / (currAlt - prevAlt);
          const tZero = denseTimes[pass.end - 1].getTime() + frac * (denseTimes[pass.end].getTime() - denseTimes[pass.end - 1].getTime());
          segTimes.push(tZero);
          segAlts.push(0.0); // Ends strictly at the bottom!
        }

        curves.push({ times: segTimes, alts: segAlts });

        // Calculate peak altitude for this passage
        let maxAlt = -999;
        let maxIdx = pass.start;
        for (let i = pass.start; i < pass.end; i++) {
          if (alts[i] > maxAlt) {
            maxAlt = alts[i];
            maxIdx = i;
          }
        }

        const peakTime = denseTimes[maxIdx];
        if (maxAlt >= 5.0 && peakTime.getTime() >= this.tStart && peakTime.getTime() <= this.tEnd) {
          const tz = this.options.tz;
          const pHour = String(tz === "utc" ? peakTime.getUTCHours() : peakTime.getHours()).padStart(2, "0");
          const pMin = String(tz === "utc" ? peakTime.getUTCMinutes() : peakTime.getMinutes()).padStart(2, "0");
          const tStr = `${pHour}:${pMin}`;

          let moonPhase = 0.0;
          if (isMoon) {
            const dKey = this._formatDateKey(peakTime);
            if (this.data.astro && this.data.astro.daily && this.data.astro.daily[dKey]) {
              moonPhase = this.data.astro.daily[dKey].moon_phase || 0.0;
            }
          }
          peaks.push({ timeMs: peakTime.getTime(), alt: maxAlt, tStr, moonPhase });
        }
      }

      return { curves, peaks };
    };

    this.celestialData = {
      sun: extractPassages(denseSunAlts, false),
      moon: extractPassages(denseMoonAlts, true),
    };
  }

  _formatDateKey(d) {
    const tz = this.options.tz;
    if (tz === "utc") {
      return d.toISOString().slice(0, 10);
    }
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }

  render() {
    if (!this.data || !this.times || this.times.length === 0 || !this.ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = this.container.getBoundingClientRect();
    const cssWidth = Math.max(880, Math.floor(rect.width));
    const cssHeight = 915;

    this.canvas.width = Math.floor(cssWidth * dpr);
    this.canvas.height = Math.floor(cssHeight * dpr);
    this.canvas.style.width = `${cssWidth}px`;
    this.canvas.style.height = `${cssHeight}px`;

    // Clear and fill physical hardware buffer with opaque white before scaling
    if (this.ctx.setTransform) {
      this.ctx.setTransform(1, 0, 0, 1, 0, 0);
    } else if (this.ctx.resetTransform) {
      this.ctx.resetTransform();
    }
    this.ctx.fillStyle = "#ffffff";
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // Apply high-DPI scaling
    this.ctx.scale(dpr, dpr);

    // Layout configuration
    this.W = cssWidth;
    this.H = cssHeight;
    this.marginLeft = 68;
    this.marginRight = 62;
    this.plotWidth = this.W - this.marginLeft - this.marginRight;

    // Panel rectangles:
    // Header: y 0 to 45
    // P1: Temperature (h: 220)
    // P2: Precipitation (h: 120)
    // P3: Clouds (h: 130)
    // P4: Wind (h: 140)
    // P5: MSLP (h: 110)
    // Timeline / Ephemeris (h: 95)
    this.panels = {
      p1: { top: 45, height: 220, bottom: 265, name: "temp" },
      p2: { top: 275, height: 125, bottom: 400, name: "precip" },
      p3: { top: 410, height: 130, bottom: 540, name: "clouds" },
      p4: { top: 550, height: 135, bottom: 685, name: "wind" },
      p5: { top: 695, height: 110, bottom: 805, name: "pressure" },
      timeline: { top: 805, height: 95, bottom: 900, name: "timeline" },
    };

    this._drawBackground();
    this._drawPanelBordersAndGrid();
    this._drawTemperaturePanel();
    this._drawPrecipitationPanel();
    this._drawCloudCoverPanel();
    this._drawWindPanel();
    this._drawPressurePanel();
    this._drawTimelineAndEphemeris();
    this._drawHeader();

    if (this.hoverIdx !== null) {
      this._drawCrosshair();
    }
  }

  _timeToX(timeMs) {
    return this.marginLeft + ((timeMs - this.tStart) / (this.tEnd - this.tStart)) * this.plotWidth;
  }

  _xToTime(x) {
    const frac = (x - this.marginLeft) / this.plotWidth;
    return this.tStart + frac * (this.tEnd - this.tStart);
  }

  _drawBackground() {
    const ctx = this.ctx;
    // Crisp clean background
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, this.W, this.H);

    // Draw Night Shading across all 5 panels (from top of P1 to bottom of P5)
    const topY = this.panels.p1.top;
    const bottomY = this.panels.p5.bottom;

    // Use sun_pairs from astro data if present, or compute from sunAlts zero-crossings
    const astro = this.data.astro;
    const sunPairs = (astro && astro.sun_pairs) ? astro.sun_pairs : [];

    // Draw full background as subtle night grey first, then cut daylight white
    ctx.fillStyle = "rgba(241, 245, 249, 0.75)";
    ctx.fillRect(this.marginLeft, topY, this.plotWidth, bottomY - topY);

    if (sunPairs.length > 0) {
      // Daylight white intervals
      ctx.fillStyle = "#ffffff";
      for (const pair of sunPairs) {
        const riseT = new Date(pair[0]).getTime();
        const setT = new Date(pair[1]).getTime();

        const x1 = Math.max(this.marginLeft, Math.min(this.marginLeft + this.plotWidth, this._timeToX(riseT)));
        const x2 = Math.max(this.marginLeft, Math.min(this.marginLeft + this.plotWidth, this._timeToX(setT)));

        if (x2 > x1) {
          ctx.fillRect(x1, topY, x2 - x1, bottomY - topY);
        }
      }
    } else {
      // Fallback from calculated sun altitude
      ctx.fillStyle = "#ffffff";
      let inDay = false;
      let dayStartT = null;
      for (let i = 0; i < this.times.length; i++) {
        const alt = this.sunAlts[i];
        const t = this.times[i].getTime();
        if (alt >= 0 && !inDay) {
          inDay = true;
          dayStartT = t;
        } else if (alt < 0 && inDay) {
          inDay = false;
          const x1 = Math.max(this.marginLeft, this._timeToX(dayStartT));
          const x2 = Math.min(this.marginLeft + this.plotWidth, this._timeToX(t));
          if (x2 > x1) ctx.fillRect(x1, topY, x2 - x1, bottomY - topY);
        }
      }
      if (inDay) {
        const x1 = Math.max(this.marginLeft, this._timeToX(dayStartT));
        const x2 = this.marginLeft + this.plotWidth;
        if (x2 > x1) ctx.fillRect(x1, topY, x2 - x1, bottomY - topY);
      }
    }
  }

  _drawPanelBordersAndGrid() {
    const ctx = this.ctx;
    const topY = this.panels.p1.top;
    const bottomY = this.panels.p5.bottom;

    // Draw vertical midnight lines and 6h / 12h lines
    const tz = this.options.tz;
    ctx.save();
    for (let i = 0; i < this.times.length; i++) {
      const dt = this.times[i];
      const hour = tz === "utc" ? dt.getUTCHours() : dt.getHours();
      const min = tz === "utc" ? dt.getUTCMinutes() : dt.getMinutes();
      if (min !== 0) continue;

      const x = this._timeToX(dt.getTime());
      if (x < this.marginLeft || x > this.marginLeft + this.plotWidth) continue;

      if (hour === 0) {
        // Midnight border (solid, clear)
        ctx.strokeStyle = "rgba(148, 163, 184, 0.6)";
        ctx.lineWidth = 1.2;
        ctx.beginPath();
        ctx.moveTo(x, topY);
        ctx.lineTo(x, bottomY + this.panels.timeline.height);
        ctx.stroke();
      } else if (hour === 6 || hour === 12 || hour === 18) {
        // 6h grid line (subtle dotted)
        ctx.strokeStyle = "rgba(203, 213, 225, 0.4)";
        ctx.lineWidth = 0.8;
        ctx.setLineDash([2, 3]);
        ctx.beginPath();
        ctx.moveTo(x, topY);
        ctx.lineTo(x, bottomY);
        ctx.stroke();
        ctx.setLineDash([]);
      }
    }
    ctx.restore();

    // Horizontal panel dividers and borders
    ctx.strokeStyle = "#cbd5e1";
    ctx.lineWidth = 1;
    for (const key of ["p1", "p2", "p3", "p4", "p5"]) {
      const p = this.panels[key];
      ctx.strokeRect(this.marginLeft, p.top, this.plotWidth, p.height);
    }
  }

  _drawHeader() {
    const ctx = this.ctx;
    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;
    const loc = this.data.location || {};
    const locName = loc.name || "Bratislava-Koliba";
    const elev = loc.elevation != null ? `${Math.round(loc.elevation)} m` : "";
    const model = this.data.model || "aifs";
    const modelName = model === "icon_d2" ? "DWD ICON-D2 2.2 km (20 members)" : (model === "icon_eu" ? "DWD ICON-EU 7.0 km (40 members)" : "ECMWF AIFS 0.25° (50 members)");

    ctx.save();
    // Title
    ctx.fillStyle = "#0f172a";
    ctx.font = "bold 15px 'Inter', sans-serif";
    ctx.textAlign = "left";
    ctx.fillText(`${locName} ${elev ? `(${elev})` : ""} — ${modelName}`, this.marginLeft, 24);

    // Subtitle / meta
    ctx.fillStyle = "#64748b";
    ctx.font = "11px 'Inter', sans-serif";
    const tzLabel = this.options.tz === "utc" ? t.utc_time : `${t.local_time} (${loc.timezone || "Europe/Bratislava"})`;
    ctx.fillText(`${t.subtitle} | ${tzLabel}`, this.marginLeft, 39);

    // Model badge
    ctx.textAlign = "right";
    ctx.fillStyle = "#1e40af";
    ctx.font = "bold 11px 'Inter', sans-serif";
    ctx.fillText(`AI ENSEMBLE FORECAST`, this.marginLeft + this.plotWidth, 24);
    ctx.restore();
  }

  _drawTemperaturePanel() {
    const ctx = this.ctx;
    const p = this.panels.p1;
    const stats = this.data.stats;
    const tStats = stats.temperature_2m;
    if (!tStats) return;

    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;

    // Adaptive Y-Scale calculation:
    // Curve and percentiles are bounded inside major grid lines (-20, -10, 0, 10, 20, 30, 40°C).
    // If there are no data between e.g. 20 and 30°C, 30°C is not displayed.
    // Major grid lines always have a clean margin so they do not touch the top or bottom panel edges.
    // Primary bounding major grid lines are governed by curve and percentiles (median, Q25, Q75)
    let pMin = Infinity, pMax = -Infinity;
    const scanVals = (arr) => {
      if (!arr) return;
      for (let i = 0; i < arr.length; i++) {
        const v = arr[i];
        if (v != null && !isNaN(v)) {
          if (v < pMin) pMin = v;
          if (v > pMax) pMax = v;
        }
      }
    };
    scanVals(tStats.median);
    scanVals(tStats.q25);
    scanVals(tStats.q75);

    if (!isFinite(pMin) || !isFinite(pMax)) {
      pMin = 5.0; pMax = 25.0;
    }

    // Bounded inside major grid lines (-20, -10, 0, 10, 20, 30, 40°C)
    let bottomMajor = Math.floor(pMin / 10) * 10;
    let topMajor = Math.ceil(pMax / 10) * 10;

    // Check extreme envelope (min / max).
    // An outlier tick shouldn't bump the major grid by 10°C if it already fits inside the margin (~2.5°C)
    let absMin = pMin, absMax = pMax;
    if (tStats.min) {
      for (let i = 0; i < tStats.min.length; i++) {
        const v = tStats.min[i];
        if (v != null && !isNaN(v) && v < absMin) absMin = v;
      }
    }
    if (tStats.max) {
      for (let i = 0; i < tStats.max.length; i++) {
        const v = tStats.max[i];
        if (v != null && !isNaN(v) && v > absMax) absMax = v;
      }
    }

    if (absMax > topMajor + 2.5) {
      topMajor = Math.ceil(absMax / 10) * 10;
    }
    if (absMin < bottomMajor - 2.5) {
      bottomMajor = Math.floor(absMin / 10) * 10;
    }

    if (topMajor <= bottomMajor) {
      topMajor = bottomMajor + 10;
    }

    // Breathing margin (~12% of span, bounded between 1.8°C and 3.5°C)
    // Ensures topMajor and bottomMajor grid lines never sit directly on the top/bottom panel borders
    const span = topMajor - bottomMajor;
    const margin = Math.max(1.8, Math.min(3.5, span * 0.12));
    const yMin = Math.min(bottomMajor - margin, absMin - 0.4);
    const yMax = Math.max(topMajor + margin, absMax + 0.4);
    const yRange = yMax - yMin;

    const valToY = (v) => p.bottom - ((v - yMin) / yRange) * p.height;

    // Distinctive colored reference lines:
    // -20°C: light blue, -10°C: light blue, 0°C: blue, 10°C: yellow, 20°C: orange, 30°C: red, 40°C: dark red
    const tempLevels = {
      "-30": { color: "#38bdf8", lbl: "-30°C" },
      "-20": { color: "#38bdf8", lbl: "-20°C" },
      "-10": { color: "#38bdf8", lbl: "-10°C" },
      "0":   { color: "#0284c7", lbl: "0°C" },
      "10":  { color: "#eab308", lbl: "10°C" },
      "20":  { color: "#f97316", lbl: "20°C" },
      "30":  { color: "#ef4444", lbl: "30°C" },
      "40":  { color: "#dc2626", lbl: "40°C" },
    };

    // Grid lines & labels strictly from bottomMajor to topMajor (e.g. 0 to 20°C)
    ctx.save();
    ctx.font = "10px 'Inter', monospace";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";

    for (let v = bottomMajor; v <= topMajor; v += 5) {
      const y = valToY(v);
      if (y < p.top || y > p.bottom) continue;

      const lvl = tempLevels[String(v)];
      if (lvl) {
        // Distinctive colored thicker dashed line (0, 10, 20, 30°C etc.)
        ctx.strokeStyle = lvl.color;
        ctx.lineWidth = 1.5;
        ctx.setLineDash([5, 4]);
      } else {
        // Minor grid line (e.g. 5, 15, 25°C)
        ctx.strokeStyle = "#e2e8f0";
        ctx.lineWidth = 0.8;
        ctx.setLineDash([2, 3]);
      }

      ctx.beginPath();
      ctx.moveTo(this.marginLeft, y);
      ctx.lineTo(this.marginLeft + this.plotWidth, y);
      ctx.stroke();
      ctx.setLineDash([]);

      // Left axis label
      if (lvl) {
        ctx.fillStyle = lvl.color;
        ctx.font = "bold 10px 'Inter', monospace";
      } else {
        ctx.fillStyle = "#64748b";
        ctx.font = "10px 'Inter', monospace";
      }
      ctx.fillText(`${v > 0 ? `+${v}` : v} °C`, this.marginLeft - 6, y);
    }

    // Celestial altitude curves (Sun and Moon)
    this._drawCelestialCurves(p);

    // Draw 100% ensemble spread band (min to max)
    ctx.fillStyle = "rgba(254, 202, 202, 0.45)";
    ctx.beginPath();
    let started = false;
    for (let i = 0; i < this.times.length; i++) {
      if (tStats.max[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(tStats.max[i]);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    for (let i = this.times.length - 1; i >= 0; i--) {
      if (tStats.min[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(tStats.min[i]);
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fill();

    // Draw 50% quartile spread band (Q25 to Q75)
    ctx.fillStyle = "rgba(248, 113, 113, 0.45)";
    ctx.beginPath();
    started = false;
    for (let i = 0; i < this.times.length; i++) {
      if (tStats.q75[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(tStats.q75[i]);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    for (let i = this.times.length - 1; i >= 0; i--) {
      if (tStats.q25[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(tStats.q25[i]);
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fill();

    // Draw Median Curve (solid red)
    ctx.strokeStyle = "#dc2626";
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    started = false;
    for (let i = 0; i < this.times.length; i++) {
      if (tStats.median[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(tStats.median[i]);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Panel title & legend
    ctx.textAlign = "left";
    ctx.fillStyle = "#1e293b";
    ctx.font = "bold 11px 'Inter', sans-serif";
    ctx.fillText(t.temp, this.marginLeft + 8, p.top + 14);

    // Legend items
    this._drawLegendBadge(this.marginLeft + 180, p.top + 9, "#dc2626", t.median);
    this._drawLegendBadge(this.marginLeft + 255, p.top + 9, "rgba(248, 113, 113, 0.8)", t.spread_50, true);
    this._drawLegendBadge(this.marginLeft + 395, p.top + 9, "rgba(254, 202, 202, 0.9)", t.spread_100, true);
    this._drawLegendBadge(this.marginLeft + 560, p.top + 9, "#f59e0b", t.sun_alt, false, [3, 2]);
    this._drawLegendBadge(this.marginLeft + 670, p.top + 9, "#60a5fa", t.moon_alt, false, [3, 2]);

    // Small Analemma reflecting given location in top-right of temperature graph (Transparent background)
    const anW = 104;
    const anH = 110;
    const anX = this.marginLeft + this.plotWidth - anW - 8;
    const anY = p.top + 18;
    const activeDate = (this.hoverIdx !== null && this.times?.[this.hoverIdx]) 
      ? this.times[this.hoverIdx] 
      : (this.times?.[0] || new Date());
    const lat = (this.data.location && this.data.location.latitude) ?? 48.15;
    const lon = (this.data.location && this.data.location.longitude) ?? 17.10;
    this._drawAnalemmaWidget(ctx, anX, anY, anW, anH, activeDate, lat, lon);

    ctx.restore();
    this.panels.p1.valToY = valToY;
  }

  _drawAnalemmaWidget(ctx, x, y, width, height, activeDate, lat = 48.15, lon = 17.10) {
    if (!this.analemmaCurve || this.analemmaCurve.length === 0) return;
    ctx.save();

    // 100% Transparent background with subtle boundary guide so underlying graph curves are never obscured
    const r = 6;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + width - r, y);
    ctx.arcTo(x + width, y, x + width, y + r, r);
    ctx.lineTo(x + width, y + height - r);
    ctx.arcTo(x + width, y + height, x + width - r, y + height, r);
    ctx.lineTo(x + r, y + height);
    ctx.arcTo(x, y + height, x, y + height - r, r);
    ctx.lineTo(x, y + r);
    ctx.arcTo(x, y, x + r, y, r);
    ctx.closePath();
    ctx.strokeStyle = "rgba(148, 163, 184, 0.25)";
    ctx.lineWidth = 0.8;
    ctx.setLineDash([2, 2]);
    ctx.stroke();
    ctx.setLineDash([]);

    // Location-aware title: "Analemma (48.2°N)"
    const isNorth = lat >= 0;
    const absLat = Math.abs(lat);
    const latStr = `${absLat.toFixed(1)}°${isNorth ? "N" : "S"}`;

    ctx.shadowColor = "rgba(255, 255, 255, 0.9)";
    ctx.shadowBlur = 3;
    ctx.fillStyle = "#1e293b";
    ctx.font = "bold 8.5px 'Inter', sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    ctx.fillText(`Analemma (${latStr})`, x + width / 2, y + 4);

    // Inner plot area
    const padX = 15;
    const padTop = 18;
    const padBottom = 18;
    const plotW = width - padX * 2;
    const plotH = height - padTop - padBottom;
    const plotLeft = x + padX;
    const plotTop = y + padTop;

    // Solar culmination altitude formula for this latitude:
    // In Northern Hemisphere: h(dec) = 90 - lat + dec (highest in June, lowest in Dec)
    // In Southern Hemisphere: h(dec) = 90 - |lat| - dec (highest in Dec, lowest in June)
    const noonAlt = (dec) => {
      if (lat >= 0) {
        return 90.0 - lat + dec;
      } else {
        return 90.0 + lat - dec;
      }
    };

    const altJun = noonAlt(23.44);
    const altDec = noonAlt(-23.44);
    const altEq = noonAlt(0);
    const altMax = Math.max(altJun, altDec);
    const altMin = Math.min(altJun, altDec);

    // Dynamic vertical mapping bounded to the location's altitude span with margin
    const yMargin = 2.0;
    const plotAltMax = altMax + yMargin;
    const plotAltMin = altMin - yMargin;

    const eotMin = -16.0, eotMax = 18.0;
    const eotToX = (eot) => plotLeft + ((eot - eotMin) / (eotMax - eotMin)) * plotW;
    const altToY = (alt) => plotTop + ((plotAltMax - alt) / (plotAltMax - plotAltMin)) * plotH;

    // Equinox centerline (h = altEq)
    const yEq = altToY(altEq);
    ctx.strokeStyle = "rgba(100, 116, 139, 0.4)";
    ctx.lineWidth = 0.8;
    ctx.setLineDash([3, 2]);
    ctx.beginPath();
    ctx.moveTo(plotLeft - 5, yEq);
    ctx.lineTo(plotLeft + plotW + 5, yEq);
    ctx.stroke();
    ctx.setLineDash([]);

    // Solstice marks & labels reflecting local altitude
    const yTopSolstice = altToY(altMax);
    const yBottomSolstice = altToY(altMin);
    const topLabel = isNorth ? `Jun ${altMax.toFixed(0)}°` : `Dec ${altMax.toFixed(0)}°`;
    const bottomLabel = isNorth ? `Dec ${altMin.toFixed(0)}°` : `Jun ${altMin.toFixed(0)}°`;

    ctx.fillStyle = "#64748b";
    ctx.font = "7px 'Inter', sans-serif";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    ctx.fillText(topLabel, plotLeft - 3, yTopSolstice);
    ctx.fillText(bottomLabel, plotLeft - 3, yBottomSolstice);
    ctx.textAlign = "left";
    ctx.fillText(`${altEq.toFixed(0)}°`, plotLeft + plotW + 3, yEq);

    // Draw full 365-day figure-8 Analemma curve reflecting location's solar elevation
    // Underlay white halo for contrast over background graph curves:
    ctx.strokeStyle = "rgba(255, 255, 255, 0.9)";
    ctx.lineWidth = 3.0;
    ctx.beginPath();
    for (let i = 0; i < this.analemmaCurve.length; i++) {
      const pt = this.analemmaCurve[i];
      const px = eotToX(pt.eot);
      const py = altToY(noonAlt(pt.dec));
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.stroke();

    // Foreground amber curve:
    ctx.strokeStyle = "#d97706";
    ctx.lineWidth = 1.6;
    ctx.beginPath();
    for (let i = 0; i < this.analemmaCurve.length; i++) {
      const pt = this.analemmaCurve[i];
      const px = eotToX(pt.eot);
      const py = altToY(noonAlt(pt.dec));
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.stroke();

    // Active date sun position reflecting location
    const curAstro = calculateSolarDeclinationAndEoT(activeDate || new Date());
    const curAlt = noonAlt(curAstro.dec);
    const sunX = eotToX(curAstro.eot);
    const sunY = altToY(curAlt);

    // Glowing halo around active sun position
    ctx.fillStyle = "rgba(251, 146, 60, 0.4)";
    ctx.beginPath();
    ctx.arc(sunX, sunY, 6, 0, Math.PI * 2);
    ctx.fill();

    // Core bright sun marker with white border
    ctx.fillStyle = "#ea580c";
    ctx.beginPath();
    ctx.arc(sunX, sunY, 3, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#ffffff";
    ctx.beginPath();
    ctx.arc(sunX, sunY, 1.2, 0, Math.PI * 2);
    ctx.fill();

    // Footer: current local altitude at noon & EoT
    ctx.shadowColor = "rgba(255, 255, 255, 0.9)";
    ctx.shadowBlur = 3;
    ctx.fillStyle = "#334155";
    ctx.font = "bold 8px 'Inter', sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "bottom";
    const eotSign = curAstro.eot >= 0 ? "+" : "";
    ctx.fillText(`Alt: ${curAlt.toFixed(1)}° (${eotSign}${curAstro.eot.toFixed(0)}m)`, x + width / 2, y + height - 2);

    ctx.restore();
  }

  _drawCelestialCurves(p, options = {}) {
    if (!this.celestialData) return;
    const iconsOnly = options.iconsOnly === true;
    const ctx = this.ctx;
    // Y-scale starts strictly at 0.0 so altitude=0.0 (rise/set at horizon) is EXACTLY at p.bottom!
    const altToY = (altDeg) => p.bottom - (Math.max(0, altDeg) / 92.0) * p.height;

    // 1. Clip strictly to the graph plot bounds so trajectories never extend out of the graph
    ctx.save();
    ctx.beginPath();
    ctx.rect(this.marginLeft, p.top, this.plotWidth, p.height);
    ctx.clip();

    // 2. Plot Sun passages (anchored strictly at p.bottom)
    ctx.strokeStyle = "#f4a261";
    ctx.lineWidth = 1.3;
    ctx.setLineDash([4, 3]);

    for (const curve of this.celestialData.sun.curves) {
      ctx.beginPath();
      let started = false;
      for (let i = 0; i < curve.times.length; i++) {
        const x = this._timeToX(curve.times[i]);
        const y = altToY(curve.alts[i]);
        if (!started) {
          ctx.moveTo(x, y);
          started = true;
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
    }

    // 3. Plot Moon passages (anchored strictly at p.bottom)
    ctx.strokeStyle = "#00b4d8";
    ctx.lineWidth = 1.2;
    ctx.setLineDash([2, 3]);

    for (const curve of this.celestialData.moon.curves) {
      ctx.beginPath();
      let started = false;
      for (let i = 0; i < curve.times.length; i++) {
        const x = this._timeToX(curve.times[i]);
        const y = altToY(curve.alts[i]);
        if (!started) {
          ctx.moveTo(x, y);
          started = true;
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
    }
    ctx.setLineDash([]);

    // 4. Solar Peaks (time + degree badge or icon only at crest)
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (const peak of this.celestialData.sun.peaks) {
      const x = this._timeToX(peak.timeMs);
      if (x < this.marginLeft + 12 || x > this.marginLeft + this.plotWidth - 12) continue;
      const y = altToY(peak.alt);

      if (iconsOnly) {
        ctx.font = "bold 13px 'Inter', sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillStyle = "#b45309";
        ctx.fillText("☀", x, y);
      } else {
        const label = `☀ ${peak.tStr} (${Math.round(peak.alt)}°)`;
        ctx.font = "bold 9px 'Inter', sans-serif";
        const tw = ctx.measureText(label).width;

        ctx.fillStyle = "rgba(255, 251, 235, 0.94)";
        ctx.fillRect(x - tw / 2 - 3, y - 16, tw + 6, 13);
        ctx.strokeStyle = "#fde68a";
        ctx.lineWidth = 0.8;
        ctx.strokeRect(x - tw / 2 - 3, y - 16, tw + 6, 13);

        ctx.fillStyle = "#b45309";
        ctx.fillText(label, x, y - 9.5);
      }
    }

    // 5. Lunar Peaks (mini moon icon + time + degree badge at crest or icon only)
    for (const peak of this.celestialData.moon.peaks) {
      const x = this._timeToX(peak.timeMs);
      if (x < this.marginLeft + 12 || x > this.marginLeft + this.plotWidth - 12) continue;
      const y = altToY(peak.alt);

      // In iconsOnly mode, center of moon icon is placed exactly at max point (x, y)
      const moonY = iconsOnly ? y : y + 8;
      this._drawMoonPhaseBadge(x, moonY, peak.moonPhase, 5.5);

      if (!iconsOnly) {
        const label = `${peak.tStr} (${Math.round(peak.alt)}°)`;
        ctx.font = "bold 8.5px 'Inter', sans-serif";
        ctx.fillStyle = "#0369a1";
        ctx.fillText(label, x, y + 21);
      }
    }

    // Restore from plot clip so right axis labels can be rendered in the margin
    ctx.restore();

    // 6. Right axis: Celestial altitudes (0° .. 90°)
    const rightEdge = this.marginLeft + this.plotWidth;
    ctx.save();
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillStyle = "#d97706";
    ctx.font = "9px 'Inter', sans-serif";

    const y90 = altToY(90);
    const y45 = altToY(45);
    const y0 = altToY(0);

    // Subtle right tick marks
    ctx.strokeStyle = "#d97706";
    ctx.lineWidth = 0.8;
    [y90, y45, y0].forEach(y => {
      ctx.beginPath();
      ctx.moveTo(rightEdge, y);
      ctx.lineTo(rightEdge + 3, y);
      ctx.stroke();
    });

    ctx.fillText("90°", rightEdge + 6, Math.max(p.top + 7, y90));
    ctx.fillText("45°", rightEdge + 6, y45);
    ctx.fillText("0°", rightEdge + 6, y0 - 4);
    ctx.fillStyle = "#92400e";
    ctx.fillText("[Alt]", rightEdge + 24, y0 - 4);
    ctx.restore();
  }

  _drawPrecipitationPanel() {
    const ctx = this.ctx;
    const p = this.panels.p2;
    const stats = this.data.stats;
    const pRain = stats.precipitation;
    const pSnow = stats.snowfall;
    if (!pRain) return;

    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;

    // Find max rain to scale
    let maxP = 2.0;
    const rMax = pRain.max || [];
    for (let i = 0; i < rMax.length; i++) {
      if (rMax[i] != null && rMax[i] > maxP) maxP = rMax[i];
    }
    const yMax = Math.ceil(maxP * 1.25 / 2.0) * 2.0;
    const valToY = (v) => p.bottom - (v / yMax) * p.height;

    // Grid lines
    ctx.save();
    ctx.font = "10px 'Inter', monospace";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";

    const step = yMax <= 5 ? 1 : (yMax <= 15 ? 2.5 : 5);
    for (let v = 0; v <= yMax; v += step) {
      const y = valToY(v);
      if (y < p.top || y > p.bottom) continue;

      ctx.strokeStyle = "#e2e8f0";
      ctx.lineWidth = 0.8;
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(this.marginLeft, y);
      ctx.lineTo(this.marginLeft + this.plotWidth, y);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = "#64748b";
      ctx.fillText(`${v.toFixed(step < 1 ? 1 : 0)} mm`, this.marginLeft - 6, y);
    }

    // Draw bars
    const nTimes = this.times.length;
    const barWidth = Math.max(2, (this.plotWidth / nTimes) * 0.75);

    const rainMed = pRain.median || [];
    const rainMax = pRain.max || [];
    const snowMed = pSnow ? (pSnow.median || []) : [];

    for (let i = 0; i < nTimes; i++) {
      const x = this._timeToX(this.times[i].getTime());
      const r = rainMed[i] || 0.0;
      const s = snowMed[i] || 0.0;
      const m = rainMax[i] || 0.0;

      if (r > 0 || s > 0) {
        // Rain bar (blue)
        const yR = valToY(r);
        ctx.fillStyle = "#2563eb";
        ctx.fillRect(x - barWidth / 2, yR, barWidth, p.bottom - yR);

        // Snow bar (cyan stacked on top or separate)
        if (s > 0) {
          const yS = valToY(r + s);
          ctx.fillStyle = "#06b6d4";
          ctx.fillRect(x - barWidth / 2, yS, barWidth, yR - yS);
        }
      }

      // Max member tick (horizontal cap)
      if (m > 0.05) {
        const yM = valToY(m);
        ctx.strokeStyle = "#1e40af";
        ctx.lineWidth = 1.4;
        ctx.beginPath();
        ctx.moveTo(x - barWidth, yM);
        ctx.lineTo(x + barWidth, yM);
        ctx.stroke();
      }
    }

    // Title & Legend (top strip)
    ctx.textAlign = "left";
    ctx.fillStyle = "#1e293b";
    ctx.font = "bold 11px 'Inter', sans-serif";
    ctx.fillText(t.precip, this.marginLeft + 8, p.top + 14);

    this._drawLegendBadge(this.marginLeft + 245, p.top + 9, "#2563eb", t.rain, true);
    this._drawLegendBadge(this.marginLeft + 310, p.top + 9, "#06b6d4", t.snow, true);
    this._drawLegendBadge(this.marginLeft + 380, p.top + 9, "#1e40af", "Max member tick", false, [0, 0]);

    // Daily precipitation accumulation badges (placed below the legend strip at p.top + 28)
    ctx.textAlign = "center";
    ctx.font = "bold 8.5px 'Inter', sans-serif";
    for (const [dKey, agg] of Object.entries(this.dailyPrecipSums)) {
      if (agg.rain > 0.05 || agg.snow > 0.05) {
        const midTime = Math.floor((this.times[agg.startIdx].getTime() + this.times[agg.endIdx].getTime()) / 2);
        const x = this._timeToX(midTime);
        if (x > this.marginLeft + 20 && x < this.marginLeft + this.plotWidth - 20) {
          const label = `Σ ${agg.rain.toFixed(1)} mm${agg.snow > 0.1 ? ` (❄${agg.snow.toFixed(1)}cm)` : ""}`;
          const textW = ctx.measureText(label).width;
          const badgeY = p.top + 28;

          ctx.fillStyle = "rgba(255, 255, 255, 0.94)";
          ctx.fillRect(x - textW / 2 - 3, badgeY - 10, textW + 6, 13);
          ctx.strokeStyle = "#93c5fd";
          ctx.lineWidth = 0.8;
          ctx.strokeRect(x - textW / 2 - 3, badgeY - 10, textW + 6, 13);

          ctx.fillStyle = "#0284c7";
          ctx.fillText(label, x, badgeY - 1);
        }
      }
    }

    ctx.restore();
    this.panels.p2.valToY = valToY;
  }

  _drawCloudCoverPanel() {
    const ctx = this.ctx;
    const p = this.panels.p3;
    const stats = this.data.stats;
    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;

    const valToY = (pct) => p.bottom - (pct / 100.0) * p.height;

    // Grid lines at 0, 25, 50, 75, 100%
    ctx.save();
    ctx.font = "10px 'Inter', monospace";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";

    for (let v = 0; v <= 100; v += 25) {
      const y = valToY(v);
      ctx.strokeStyle = "#e2e8f0";
      ctx.lineWidth = 0.8;
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(this.marginLeft, y);
      ctx.lineTo(this.marginLeft + this.plotWidth, y);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = "#64748b";
      ctx.fillText(`${v}%`, this.marginLeft - 6, y);
    }

    // 1. Total Cloud Cover Bars with Percentiles (Yellow color)
    const cTotal = stats.cloud_cover;
    const nTimes = this.times.length;
    const barWidth = Math.max(2.5, (this.plotWidth / nTimes) * 0.72);

    if (cTotal && cTotal.median) {
      for (let i = 0; i < nTimes; i++) {
        const x = this._timeToX(this.times[i].getTime());
        const minVal = cTotal.min ? cTotal.min[i] : null;
        const maxVal = cTotal.max ? cTotal.max[i] : null;
        const q25 = cTotal.q25 ? cTotal.q25[i] : null;
        const q75 = cTotal.q75 ? cTotal.q75[i] : null;
        const med = cTotal.median ? cTotal.median[i] : null;

        if (med == null) continue;

        if (minVal != null && maxVal != null && (maxVal > 0 || minVal > 0)) {
          // Full ensemble spread: Min - Max (light translucent yellow)
          const yMin = valToY(minVal);
          const yMax = valToY(maxVal);
          ctx.fillStyle = "rgba(254, 240, 138, 0.52)"; // #fef08a
          ctx.fillRect(x - barWidth / 2, yMax, barWidth, Math.max(1.5, yMin - yMax));

          // 50% interquartile spread: Q25 - Q75 (rich warm yellow)
          if (q25 != null && q75 != null) {
            const yQ25 = valToY(q25);
            const yQ75 = valToY(q75);
            ctx.fillStyle = "rgba(250, 204, 21, 0.82)"; // #facc15
            ctx.fillRect(x - barWidth / 2, yQ75, barWidth, Math.max(1.5, yQ25 - yQ75));
          }

          // Median tick mark across the bar
          const yMed = valToY(med);
          ctx.strokeStyle = "#ca8a04"; // golden yellow
          ctx.lineWidth = 1.8;
          ctx.beginPath();
          ctx.moveTo(x - barWidth / 2, yMed);
          ctx.lineTo(x + barWidth / 2, yMed);
          ctx.stroke();
        } else if (med > 0) {
          // Deterministic / single member: bar from 0 up to median
          const yMed = valToY(med);
          ctx.fillStyle = "rgba(250, 204, 21, 0.82)";
          ctx.fillRect(x - barWidth / 2, yMed, barWidth, Math.max(1.5, p.bottom - yMed));
        }
      }

      // Median trajectory line connecting the medians across the bars
      ctx.strokeStyle = "#ca8a04";
      ctx.lineWidth = 1.8;
      ctx.beginPath();
      let started = false;
      for (let i = 0; i < nTimes; i++) {
        const v = cTotal.median[i];
        if (v == null) continue;
        const x = this._timeToX(this.times[i].getTime());
        const y = valToY(v);
        if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }

    // 2. High Clouds (cyan curve, median only)
    this._drawCurve(stats.cloud_cover_high, valToY, "#06b6d4", 1.8);

    // 3. Mid Clouds (emerald green curve, median only)
    this._drawCurve(stats.cloud_cover_mid, valToY, "#10b981", 1.8);

    // 4. Low Clouds (crimson curve, median only)
    this._drawCurve(stats.cloud_cover_low, valToY, "#e11d48", 1.8);

    // Title & Legend
    ctx.textAlign = "left";
    ctx.fillStyle = "#1e293b";
    ctx.font = "bold 11px 'Inter', sans-serif";
    ctx.fillText(t.clouds, this.marginLeft + 8, p.top + 14);

    this._drawLegendBadge(this.marginLeft + 130, p.top + 9, "#facc15", t.total_clouds, true);
    this._drawLegendBadge(this.marginLeft + 235, p.top + 9, "#06b6d4", t.high_clouds, false);
    this._drawLegendBadge(this.marginLeft + 355, p.top + 9, "#10b981", t.mid_clouds, false);
    this._drawLegendBadge(this.marginLeft + 480, p.top + 9, "#e11d48", t.low_clouds, false);

    ctx.restore();
    this.panels.p3.valToY = valToY;
  }

  _drawCurve(varStat, valToY, color, width = 1.5, dash = []) {
    if (!varStat || !varStat.median) return;
    const ctx = this.ctx;
    ctx.save();
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    if (dash.length > 0) ctx.setLineDash(dash);

    ctx.beginPath();
    let started = false;
    for (let i = 0; i < this.times.length; i++) {
      const v = varStat.median[i];
      if (v == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(v);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.restore();
  }

  _drawWindPanel() {
    const ctx = this.ctx;
    const p = this.panels.p4;
    const stats = this.data.stats;
    const wSpeed = stats.wind_speed_10m;
    const wDir = stats.wind_direction_10m;
    if (!wSpeed) return;

    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;

    // Find max wind to scale
    let maxW = 10.0;
    const sMax = wSpeed.max || [];
    for (let i = 0; i < sMax.length; i++) {
      if (sMax[i] != null && sMax[i] > maxW) maxW = sMax[i];
    }
    const yMax = Math.ceil(maxW / 5.0) * 5.0;
    const valToY = (v) => p.bottom - (v / yMax) * p.height;

    // Bounds for vertical wind azimuth levels: 5 levels N, W, S, E, N from top to bottom (360° loop)
    const yTop = p.top + 28;
    const yBottom = p.bottom - 16;
    const ySpan = yBottom - yTop;

    const dirLevels = [
      { y: yTop, label: "N", col: "#64748b" },
      { y: yTop + ySpan * 0.25, label: "W", col: "#64748b" },
      { y: yTop + ySpan * 0.50, label: "S", col: "#64748b" },
      { y: yTop + ySpan * 0.75, label: "E", col: "#64748b" },
      { y: yBottom, label: "N", col: "#64748b" }
    ];

    const dirToY = (dir) => {
      const d = ((dir % 360) + 360) % 360;
      // 360° -> yTop (N), 270° -> W, 180° -> S, 90° -> E, 0° -> yBottom (N)
      return yTop + ((360.0 - d) / 360.0) * ySpan;
    };

    // Grid lines for 5 wind direction levels: N, W, S, E, N
    ctx.save();
    ctx.strokeStyle = "rgba(148, 163, 184, 0.45)";
    ctx.lineWidth = 0.85;
    ctx.setLineDash([3, 3]);

    for (const lvl of dirLevels) {
      ctx.beginPath();
      ctx.moveTo(this.marginLeft, lvl.y);
      ctx.lineTo(this.marginLeft + this.plotWidth, lvl.y);
      ctx.stroke();
    }
    ctx.setLineDash([]);

    // Left axis: Wind Speed (m/s)
    ctx.font = "10px 'Inter', monospace";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    ctx.fillStyle = "#64748b";

    for (let v = 0; v <= yMax; v += (yMax <= 15 ? 2.5 : 5)) {
      const y = valToY(v);
      if (y < p.top || y > p.bottom) continue;

      ctx.strokeStyle = "#e2e8f0";
      ctx.lineWidth = 0.6;
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(this.marginLeft, y);
      ctx.lineTo(this.marginLeft + this.plotWidth, y);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillText(`${v.toFixed(1)} m/s`, this.marginLeft - 6, y);
    }

    // Right axis: Direction legend (N, W, S, E, N)
    ctx.font = "bold 9.5px 'Inter', sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";

    for (const lvl of dirLevels) {
      // Small tick mark on the right border pointing to the label
      ctx.strokeStyle = "#94a3b8";
      ctx.lineWidth = 1.0;
      ctx.beginPath();
      ctx.moveTo(this.marginLeft + this.plotWidth, lvl.y);
      ctx.lineTo(this.marginLeft + this.plotWidth + 4, lvl.y);
      ctx.stroke();

      const rightX = this.marginLeft + this.plotWidth + 7;
      ctx.fillStyle = lvl.col;
      ctx.fillText(lvl.label, rightX, lvl.y);
    }

    // Spread band (light slate)
    ctx.fillStyle = "rgba(148, 163, 184, 0.25)";
    ctx.beginPath();
    let started = false;
    for (let i = 0; i < this.times.length; i++) {
      if (wSpeed.max[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(wSpeed.max[i]);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    for (let i = this.times.length - 1; i >= 0; i--) {
      if (wSpeed.min[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(wSpeed.min[i]);
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fill();

    // Wind speed median curve
    ctx.strokeStyle = "#334155";
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    started = false;
    for (let i = 0; i < this.times.length; i++) {
      if (wSpeed.median[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(wSpeed.median[i]);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Draw Rotating Meteorological Wind Arrows distributed as a wave by 5-direction azimuth (N, W, S, E, N)
    if (wDir && wDir.median) {
      // Wind direction trajectory curve colored continuously by wind direction
      ctx.save();
      ctx.lineWidth = 2.2;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";

      for (let i = 0; i < this.times.length - 1; i++) {
        let dir1 = wDir.median[i];
        let dir2 = wDir.median[i + 1];
        if (dir1 == null || dir2 == null) continue;

        dir1 = ((dir1 % 360) + 360) % 360;
        dir2 = ((dir2 % 360) + 360) % 360;

        const x1 = this._timeToX(this.times[i].getTime());
        const x2 = this._timeToX(this.times[i + 1].getTime());

        // Variable curve thickness according to wind speed (PoC):
        // Variable curve thickness according to wind speed:
        // 1.2px for light winds (< 2 m/s), up to ~5.5px for strong winds (>= 15 m/s)
        const spd1 = wSpeed.median[i] != null ? wSpeed.median[i] : 0;
        const spd2 = wSpeed.median[i + 1] != null ? wSpeed.median[i + 1] : spd1;
        const avgSpd = (spd1 + spd2) / 2.0;
        ctx.lineWidth = Math.max(1.2, Math.min(5.8, 1.2 + (avgSpd / 15.0) * 4.0));

        const col1 = this._getWindSpeedColor(spd1);
        const col2 = this._getWindSpeedColor(spd2);

        // Handle wrap-around across North (360° / 0°)
        if (dir1 - dir2 > 180) {
          // Turning clockwise through North (e.g. 350° to 10°)
          const frac = (360 - dir1) / ((360 - dir1) + dir2);
          const xMid = x1 + (x2 - x1) * frac;
          const y1 = dirToY(dir1);
          const y2 = dirToY(dir2);
          const spdMid = spd1 + (spd2 - spd1) * frac;
          const colMid = this._getWindSpeedColor(spdMid);

          // Sub-segment 1: to top N (360°)
          const grad1 = ctx.createLinearGradient(x1, y1, xMid, yTop);
          grad1.addColorStop(0, col1);
          grad1.addColorStop(1, colMid);
          ctx.strokeStyle = grad1;
          ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(xMid, yTop); ctx.stroke();

          // Sub-segment 2: from bottom N (0°)
          const grad2 = ctx.createLinearGradient(xMid, yBottom, x2, y2);
          grad2.addColorStop(0, colMid);
          grad2.addColorStop(1, col2);
          ctx.strokeStyle = grad2;
          ctx.beginPath(); ctx.moveTo(xMid, yBottom); ctx.lineTo(x2, y2); ctx.stroke();
        } else if (dir2 - dir1 > 180) {
          // Turning counter-clockwise through North (e.g. 10° to 350°)
          const frac = dir1 / (dir1 + (360 - dir2));
          const xMid = x1 + (x2 - x1) * frac;
          const y1 = dirToY(dir1);
          const y2 = dirToY(dir2);
          const spdMid = spd1 + (spd2 - spd1) * frac;
          const colMid = this._getWindSpeedColor(spdMid);

          // Sub-segment 1: to bottom N (0°)
          const grad1 = ctx.createLinearGradient(x1, y1, xMid, yBottom);
          grad1.addColorStop(0, col1);
          grad1.addColorStop(1, colMid);
          ctx.strokeStyle = grad1;
          ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(xMid, yBottom); ctx.stroke();

          // Sub-segment 2: from top N (360°)
          const grad2 = ctx.createLinearGradient(xMid, yTop, x2, y2);
          grad2.addColorStop(0, colMid);
          grad2.addColorStop(1, col2);
          ctx.strokeStyle = grad2;
          ctx.beginPath(); ctx.moveTo(xMid, yTop); ctx.lineTo(x2, y2); ctx.stroke();
        } else {
          // Standard continuous segment
          const y1 = dirToY(dir1);
          const y2 = dirToY(dir2);
          const grad = ctx.createLinearGradient(x1, y1, x2, y2);
          grad.addColorStop(0, col1);
          grad.addColorStop(1, col2);
          ctx.strokeStyle = grad;
          ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
        }
      }
      ctx.restore();

      const stepInterval = Math.max(1, Math.round(this.times.length / 28)); // ~28 arrows across width
      for (let i = 0; i < this.times.length; i += stepInterval) {
        let dir = wDir.median[i];
        const spd = wSpeed.median[i];
        if (dir == null || spd == null) continue;

        dir = ((dir % 360) + 360) % 360;
        let plotDir = dir;
        if (plotDir === 0 && i > 0 && wDir.median[i - 1] > 180) {
          plotDir = 360;
        }

        const x = this._timeToX(this.times[i].getTime());
        const y = dirToY(plotDir);

        this._drawWindArrow(x, y, dir, spd);
      }
    }

    // Title & Legend
    ctx.textAlign = "left";
    ctx.fillStyle = "#1e293b";
    ctx.font = "bold 11px 'Inter', sans-serif";
    ctx.fillText(t.wind, this.marginLeft + 8, p.top + 14);

    this._drawLegendBadge(this.marginLeft + 250, p.top + 9, "#334155", t.median);
    this._drawLegendBadge(this.marginLeft + 325, p.top + 9, "rgba(148, 163, 184, 0.6)", t.spread_100, true);

    // Wind Speed Color Scale Bar (Horizontal segmented scale)
    const scaleX = this.marginLeft + 435;
    const scaleY = p.top + 7;
    const tiers = [
      { label: "< 2", col: "#94a3b8", w: 26 },
      { label: "2–5", col: "#10b981", w: 28 },
      { label: "5–10", col: "#2563eb", w: 32 },
      { label: "10–15", col: "#f59e0b", w: 36 },
      { label: "> 15 m/s", col: "#ef4444", w: 46 }
    ];

    ctx.font = "bold 8px 'Inter', sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";

    let curX = scaleX;
    const barH = 13;
    for (let idx = 0; idx < tiers.length; idx++) {
      const tier = tiers[idx];
      ctx.fillStyle = tier.col;

      ctx.beginPath();
      if (idx === 0) {
        ctx.roundRect ? ctx.roundRect(curX, scaleY, tier.w, barH, [3, 0, 0, 3]) : ctx.rect(curX, scaleY, tier.w, barH);
      } else if (idx === tiers.length - 1) {
        ctx.roundRect ? ctx.roundRect(curX, scaleY, tier.w, barH, [0, 3, 3, 0]) : ctx.rect(curX, scaleY, tier.w, barH);
      } else {
        ctx.rect(curX, scaleY, tier.w, barH);
      }
      ctx.fill();

      ctx.fillStyle = "#ffffff";
      ctx.fillText(tier.label, curX + tier.w / 2, scaleY + barH / 2);
      curX += tier.w;
    }

    // Wind Curve Thickness Legend (thickness ~ wind speed)
    const thickX = curX + 16;
    ctx.font = "bold 9px 'Inter', sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillStyle = "#475569";
    const labelText = (t.curve_thickness || "Curve thickness") + ":";
    ctx.fillText(labelText, thickX, scaleY + barH / 2);

    const lblW = ctx.measureText(labelText).width;
    const wedgeX1 = thickX + lblW + 24;
    const wedgeW = 36;
    const wedgeX2 = wedgeX1 + wedgeW;
    const centerY = scaleY + barH / 2;

    // Small min speed label
    ctx.font = "8px 'Inter', sans-serif";
    ctx.fillStyle = "#64748b";
    ctx.textAlign = "right";
    ctx.fillText("< 2", wedgeX1 - 5, centerY);

    // Tapered wedge showing variable thickness (1.2px -> 5.5px)
    const r1 = 0.7;
    const r2 = 2.75;
    ctx.beginPath();
    ctx.moveTo(wedgeX1, centerY - r1);
    ctx.lineTo(wedgeX2, centerY - r2);
    ctx.arc(wedgeX2, centerY, r2, -Math.PI / 2, Math.PI / 2);
    ctx.lineTo(wedgeX1, centerY + r1);
    ctx.arc(wedgeX1, centerY, r1, Math.PI / 2, -Math.PI / 2);
    ctx.closePath();

    // Gradient filling the tapered wedge matching speed scale colors
    const wedgeGrad = ctx.createLinearGradient(wedgeX1, centerY, wedgeX2, centerY);
    wedgeGrad.addColorStop(0, "#94a3b8");
    wedgeGrad.addColorStop(0.2, "#10b981");
    wedgeGrad.addColorStop(0.5, "#2563eb");
    wedgeGrad.addColorStop(0.8, "#f59e0b");
    wedgeGrad.addColorStop(1, "#ef4444");
    ctx.fillStyle = wedgeGrad;
    ctx.fill();

    // Max speed label
    ctx.textAlign = "left";
    ctx.fillStyle = "#64748b";
    ctx.fillText("≥ 15 m/s", wedgeX2 + 4, centerY);

    ctx.restore();
    this.panels.p4.valToY = valToY;
  }

  _getWindSpeedColor(spd) {
    if (spd == null || isNaN(spd)) return "#94a3b8";
    // Speed stops matching the standard meteorological tiers:
    // < 2: Slate (#94a3b8)
    // 2-5: Emerald Green (#10b981)
    // 5-10: Royal Blue (#2563eb)
    // 10-15: Amber / Orange (#f59e0b)
    // >= 15: Coral Red / Crimson (#ef4444)
    const stops = [
      { s: 0.0,  r: 148, g: 163, b: 184 }, // 0 m/s: Slate (#94a3b8)
      { s: 2.0,  r: 148, g: 163, b: 184 }, // 2 m/s: Slate (#94a3b8)
      { s: 4.0,  r: 16,  g: 185, b: 129 }, // 4 m/s: Emerald (#10b981)
      { s: 7.5,  r: 37,  g: 99,  b: 235 }, // 7.5 m/s: Royal Blue (#2563eb)
      { s: 12.0, r: 245, g: 158, b: 11  }, // 12 m/s: Amber (#f59e0b)
      { s: 16.0, r: 239, g: 68,  b: 68  }, // 16+ m/s: Coral Red (#ef4444)
      { s: 25.0, r: 220, g: 38,  b: 38  }  // 25+ m/s: Crimson (#dc2626)
    ];
    if (spd <= stops[0].s) return `rgb(${stops[0].r}, ${stops[0].g}, ${stops[0].b})`;
    let i = 0;
    while (i < stops.length - 1 && spd > stops[i + 1].s) {
      i++;
    }
    if (i >= stops.length - 1) {
      const last = stops[stops.length - 1];
      return `rgb(${last.r}, ${last.g}, ${last.b})`;
    }
    const s1 = stops[i];
    const s2 = stops[i + 1];
    const t = (spd - s1.s) / (s2.s - s1.s);
    const r = Math.round(s1.r + (s2.r - s1.r) * t);
    const g = Math.round(s1.g + (s2.g - s1.g) * t);
    const b = Math.round(s1.b + (s2.b - s1.b) * t);
    return `rgb(${r}, ${g}, ${b})`;
  }

  _getWindDirColor(dir) {
    if (dir == null) return "#94a3b8";
    const d = ((dir % 360) + 360) % 360;
    const stops = [
      { deg: 0,   r: 37,  g: 99,  b: 235 }, // N: Royal Blue
      { deg: 45,  r: 6,   g: 182, b: 212 }, // NE: Cyan
      { deg: 90,  r: 16,  g: 185, b: 129 }, // E: Emerald
      { deg: 135, r: 245, g: 158, b: 11  }, // SE: Amber
      { deg: 180, r: 239, g: 68,  b: 68  }, // S: Coral Red
      { deg: 225, r: 217, g: 70,  b: 239 }, // SW: Fuchsia
      { deg: 270, r: 139, g: 92,  b: 246 }, // W: Purple
      { deg: 315, r: 99,  g: 102, b: 241 }, // NW: Indigo
      { deg: 360, r: 37,  g: 99,  b: 235 }, // N: Royal Blue
    ];
    let i = 0;
    while (i < stops.length - 1 && d > stops[i + 1].deg) {
      i++;
    }
    const s1 = stops[i];
    const s2 = stops[i + 1];
    const t = (d - s1.deg) / (s2.deg - s1.deg);
    const r = Math.round(s1.r + (s2.r - s1.r) * t);
    const g = Math.round(s1.g + (s2.g - s1.g) * t);
    const b = Math.round(s1.b + (s2.b - s1.b) * t);
    return `rgb(${r}, ${g}, ${b})`;
  }

  _drawWindArrow(x, y, dirDeg, speedMs) {
    const ctx = this.ctx;
    ctx.save();
    ctx.translate(x, y);
    // Meteorological: arrow points where the wind is blowing towards
    ctx.rotate(dirDeg * Math.PI / 180.0);

    // Color by speed matching scale bar and curve
    const col = this._getWindSpeedColor(speedMs);

    // Dynamic length: shorter for low winds (8px), longer for high winds (up to 28px)
    const arrowLen = Math.max(8, Math.min(28, 7 + speedMs * 1.3));
    const halfLen = arrowLen / 2;
    const headSize = Math.max(3, Math.min(6, arrowLen * 0.24));
    const shaftWidth = speedMs >= 15 ? 2.0 : (speedMs >= 10 ? 1.7 : (speedMs >= 5 ? 1.4 : 1.1));

    // Crisp white halo/backing so arrow stands out distinctly on top of the colored curve
    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = shaftWidth + 2.0;
    ctx.beginPath();
    ctx.moveTo(0, -halfLen);
    ctx.lineTo(0, halfLen - headSize);
    ctx.stroke();

    ctx.fillStyle = "#ffffff";
    ctx.beginPath();
    ctx.moveTo(0, halfLen + 1);
    ctx.lineTo(-headSize * 0.85, halfLen - headSize - 0.5);
    ctx.lineTo(headSize * 0.85, halfLen - headSize - 0.5);
    ctx.closePath();
    ctx.fill();

    // Draw arrow foreground
    ctx.fillStyle = col;
    ctx.strokeStyle = col;
    ctx.lineWidth = shaftWidth;

    // Draw shaft
    ctx.beginPath();
    ctx.moveTo(0, -halfLen);
    ctx.lineTo(0, halfLen - headSize);
    ctx.stroke();

    // Draw arrowhead
    ctx.beginPath();
    ctx.moveTo(0, halfLen);
    ctx.lineTo(-headSize * 0.7, halfLen - headSize);
    ctx.lineTo(headSize * 0.7, halfLen - headSize);
    ctx.closePath();
    ctx.fill();

    ctx.restore();
  }

  _drawPressurePanel() {
    const ctx = this.ctx;
    const p = this.panels.p5;
    const stats = this.data.stats;
    const press = stats.pressure_msl;
    if (!press) return;

    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;

    // Find min/max pressure
    let pMin = 9999, pMax = -9999;
    const mins = press.min || [];
    const maxs = press.max || [];
    for (let i = 0; i < mins.length; i++) {
      if (mins[i] != null && mins[i] < pMin) pMin = mins[i];
      if (maxs[i] != null && maxs[i] > pMax) pMax = maxs[i];
    }
    if (pMin === 9999) { pMin = 1000; pMax = 1025; }

    const yMin = Math.floor((pMin - 2) / 5) * 5;
    const yMax = Math.ceil((pMax + 2) / 5) * 5;
    const yRange = Math.max(10, yMax - yMin);

    const valToY = (v) => p.bottom - ((v - yMin) / yRange) * p.height;

    // Grid lines & labels
    ctx.save();
    ctx.font = "10px 'Inter', monospace";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";

    for (let v = yMin; v <= yMax; v += 5) {
      const y = valToY(v);
      if (y < p.top || y > p.bottom) continue;

      ctx.strokeStyle = "#e2e8f0";
      ctx.lineWidth = 0.8;
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(this.marginLeft, y);
      ctx.lineTo(this.marginLeft + this.plotWidth, y);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = "#64748b";
      ctx.fillText(`${v} hPa`, this.marginLeft - 6, y);
    }

    // 1013.25 hPa reference line (dashed grey)
    if (1013.25 >= yMin && 1013.25 <= yMax) {
      const yNorm = valToY(1013.25);
      ctx.strokeStyle = "#94a3b8";
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(this.marginLeft, yNorm);
      ctx.lineTo(this.marginLeft + this.plotWidth, yNorm);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Spread band (light purple)
    ctx.fillStyle = "rgba(168, 85, 247, 0.2)";
    ctx.beginPath();
    let started = false;
    for (let i = 0; i < this.times.length; i++) {
      if (press.max[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(press.max[i]);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    for (let i = this.times.length - 1; i >= 0; i--) {
      if (press.min[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(press.min[i]);
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fill();

    // Pressure median curve
    ctx.strokeStyle = "#7c3aed";
    ctx.lineWidth = 2;
    ctx.beginPath();
    started = false;
    for (let i = 0; i < this.times.length; i++) {
      if (press.median[i] == null) continue;
      const x = this._timeToX(this.times[i].getTime());
      const y = valToY(press.median[i]);
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Title & Legend
    ctx.textAlign = "left";
    ctx.fillStyle = "#1e293b";
    ctx.font = "bold 11px 'Inter', sans-serif";
    ctx.fillText(t.pressure, this.marginLeft + 8, p.top + 14);

    this._drawLegendBadge(this.marginLeft + 310, p.top + 9, "#7c3aed", t.median);
    this._drawLegendBadge(this.marginLeft + 385, p.top + 9, "rgba(168, 85, 247, 0.5)", t.spread_100, true);
    this._drawLegendBadge(this.marginLeft + 520, p.top + 9, "#f4a261", t.sun_alt, false, [4, 3]);
    this._drawLegendBadge(this.marginLeft + 630, p.top + 9, "#00b4d8", t.moon_alt, false, [2, 3]);

    // Draw Sun and Moon trajectories anchored at the bottom (icons only, no time or max degrees)
    this._drawCelestialCurves(p, { iconsOnly: true });

    ctx.restore();
    this.panels.p5.valToY = valToY;
  }

  _drawTimelineAndEphemeris() {
    const ctx = this.ctx;
    const p = this.panels.timeline;
    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;
    const tz = this.options.tz;

    ctx.save();
    // Timeline background box
    ctx.fillStyle = "#f8fafc";
    ctx.fillRect(this.marginLeft, p.top, this.plotWidth, p.height);
    ctx.strokeStyle = "#cbd5e1";
    ctx.lineWidth = 1;
    ctx.strokeRect(this.marginLeft, p.top, this.plotWidth, p.height);

    // Group dates and draw day headers
    const daysMap = [];
    let currentDayKey = null;
    let dayStartIdx = 0;

    for (let i = 0; i < this.times.length; i++) {
      const dt = this.times[i];
      const dKey = this._formatDateKey(dt);
      if (dKey !== currentDayKey) {
        if (currentDayKey !== null) {
          daysMap.push({ key: currentDayKey, startIdx: dayStartIdx, endIdx: i - 1 });
        }
        currentDayKey = dKey;
        dayStartIdx = i;
      }
    }
    if (currentDayKey !== null) {
      daysMap.push({ key: currentDayKey, startIdx: dayStartIdx, endIdx: this.times.length - 1 });
    }

    const astroDaily = (this.data.astro && this.data.astro.daily) ? this.data.astro.daily : {};

    for (const d of daysMap) {
      const startX = Math.max(this.marginLeft, this._timeToX(this.times[d.startIdx].getTime()));
      const endX = Math.min(this.marginLeft + this.plotWidth, this._timeToX(this.times[d.endIdx].getTime()));
      const midX = (startX + endX) / 2;
      const dayWidth = endX - startX;

      if (dayWidth < 30) continue;

      const sampleDate = this.times[d.startIdx];
      const dayName = t.days_short[tz === "utc" ? sampleDate.getUTCDay() : sampleDate.getDay()];
      const dayNum = tz === "utc" ? sampleDate.getUTCDate() : sampleDate.getDate();
      const monthNum = (tz === "utc" ? sampleDate.getUTCMonth() : sampleDate.getMonth()) + 1;

      // Day header label (e.g. Po 21.09)
      ctx.fillStyle = "#0f172a";
      ctx.font = "bold 11px 'Inter', sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`${dayName} ${dayNum}.${monthNum}.`, midX, p.top + 16);

      // 6-hour time markers
      ctx.font = "9px 'Inter', monospace";
      ctx.fillStyle = "#64748b";
      for (let i = d.startIdx; i <= d.endIdx; i++) {
        const dt = this.times[i];
        const h = tz === "utc" ? dt.getUTCHours() : dt.getHours();
        const m = tz === "utc" ? dt.getUTCMinutes() : dt.getMinutes();
        if (m === 0 && (h === 0 || h === 6 || h === 12 || h === 18)) {
          const tx = this._timeToX(dt.getTime());
          if (tx >= this.marginLeft && tx <= this.marginLeft + this.plotWidth) {
            ctx.fillText(String(h).padStart(2, "0"), tx, p.top + 32);
          }
        }
      }

      // Astronomical Badges (Sunrise, Sunset, Moonrise, Moonset, Moon Phase)
      const astroItem = astroDaily[d.key];
      if (astroItem && dayWidth > 38) {
        const fs = dayWidth < 65 ? "8px" : "8.5px";
        ctx.font = `${fs} 'Inter', sans-serif`;

        const formatTime = (iso) => {
          if (!iso) return "--:--";
          const dt = new Date(iso);
          if (isNaN(dt.getTime())) return "--:--";
          const h = String(tz === "utc" ? dt.getUTCHours() : dt.getHours()).padStart(2, "0");
          const m = String(tz === "utc" ? dt.getUTCMinutes() : dt.getMinutes()).padStart(2, "0");
          return `${h}:${m}`;
        };

        // 1. Sun rise & set
        if (astroItem.sunrise && astroItem.sunset) {
          const rStr = formatTime(astroItem.sunrise);
          const sStr = formatTime(astroItem.sunset);
          ctx.fillStyle = "#b45309"; // amber for sun
          ctx.textAlign = "center";
          ctx.fillText(`☀ ${rStr} – ${sStr}`, midX, p.top + 46);
        }

        // 2. Moon rise & set (as in static version)
        if (astroItem.moonrise || astroItem.moonset) {
          const mrStr = formatTime(astroItem.moonrise);
          const msStr = formatTime(astroItem.moonset);
          ctx.fillStyle = "#0284c7"; // blue for moon
          ctx.textAlign = "center";
          ctx.fillText(`☾ ${mrStr} – ${msStr}`, midX, p.top + 60);
        }

        // 3. Moon phase vector badge & illumination
        if (astroItem.moon_phase != null) {
          const phase = astroItem.moon_phase;
          const illum = astroItem.illum_pct != null ? `${astroItem.illum_pct}%` : "";
          this._drawMoonPhaseBadge(midX - 16, p.top + 77, phase, 6.5);
          ctx.fillStyle = "#475569";
          ctx.textAlign = "left";
          ctx.font = `${fs} 'Inter', sans-serif`;
          ctx.fillText(illum, midX - 5, p.top + 80);
        }
      }
    }

    ctx.restore();
  }

  _drawMoonPhaseBadge(cx, cy, phase, radius) {
    const ctx = this.ctx;
    ctx.save();

    const p = ((phase % 1.0) + 1.0) % 1.0;
    const darkColor = "#1e293b"; // dark unlit moon base
    const litColor = "#ffffff";  // luminous moonish pearl white
    const strokeColor = "#64748b";

    // 1. Full Moon (p ~ 0.50): fully lit disk in luminous moonish white
    if (Math.abs(p - 0.5) < 0.035) {
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
      ctx.fillStyle = litColor;
      ctx.fill();
      ctx.strokeStyle = strokeColor;
      ctx.lineWidth = 0.9;
      ctx.stroke();
      ctx.restore();
      return;
    }

    // 2. New Moon (p ~ 0.0 or 1.0): dark unlit disk with delicate perimeter
    if (p < 0.035 || p > 0.965) {
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
      ctx.fillStyle = darkColor;
      ctx.fill();
      ctx.strokeStyle = strokeColor;
      ctx.lineWidth = 0.8;
      ctx.stroke();
      ctx.restore();
      return;
    }

    // 3. Intermediate phases: draw dark disk background first
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
    ctx.fillStyle = darkColor;
    ctx.fill();
    ctx.strokeStyle = strokeColor;
    ctx.lineWidth = 0.8;
    ctx.stroke();

    // 4. Construct illuminated polygon patch (outer limb + inner terminator curve)
    const n = 36;
    const k = Math.cos(2 * Math.PI * p);
    ctx.beginPath();
    let started = false;

    // Outer limb arc from -pi/2 (top) to +pi/2 (bottom)
    for (let i = 0; i <= n; i++) {
      const phi = -Math.PI / 2 + (Math.PI * i) / n;
      const x = cx + (p < 0.5 ? 1 : -1) * radius * Math.cos(phi);
      const y = cy + radius * Math.sin(phi);
      if (!started) {
        ctx.moveTo(x, y);
        started = true;
      } else {
        ctx.lineTo(x, y);
      }
    }

    // Terminator curve from +pi/2 (bottom) back to -pi/2 (top)
    for (let i = n; i >= 0; i--) {
      const phi = -Math.PI / 2 + (Math.PI * i) / n;
      const x = cx + (p < 0.5 ? 1 : -1) * radius * k * Math.cos(phi);
      const y = cy + radius * Math.sin(phi);
      ctx.lineTo(x, y);
    }

    ctx.closePath();
    ctx.fillStyle = litColor;
    ctx.fill();

    // Outer rim stroke
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
    ctx.strokeStyle = strokeColor;
    ctx.lineWidth = 0.8;
    ctx.stroke();

    ctx.restore();
  }

  _drawLegendBadge(x, y, color, label, isFill = false, dash = []) {
    const ctx = this.ctx;
    ctx.save();
    ctx.font = "10px 'Inter', sans-serif";
    ctx.fillStyle = "#334155";
    ctx.textAlign = "left";

    if (isFill) {
      ctx.fillStyle = color;
      ctx.fillRect(x, y - 4, 14, 8);
      ctx.strokeStyle = "rgba(0,0,0,0.15)";
      ctx.lineWidth = 0.5;
      ctx.strokeRect(x, y - 4, 14, 8);
    } else {
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      if (dash.length > 0) ctx.setLineDash(dash);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + 14, y);
      ctx.stroke();
    }

    ctx.fillStyle = "#334155";
    ctx.fillText(label, x + 18, y + 3);
    ctx.restore();
  }

  _drawCrosshair() {
    if (this.hoverIdx === null || !this.times[this.hoverIdx]) return;
    const ctx = this.ctx;
    const x = this._timeToX(this.times[this.hoverIdx].getTime());
    const topY = this.panels.p1.top;
    const bottomY = this.panels.p5.bottom;

    ctx.save();
    // Synchronized vertical line
    ctx.strokeStyle = "#2563eb";
    ctx.lineWidth = 1.2;
    ctx.setLineDash([3, 2]);
    ctx.beginPath();
    ctx.moveTo(x, topY);
    ctx.lineTo(x, bottomY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Snapping dots on curves
    const stats = this.data.stats;
    const drawDot = (y, color) => {
      ctx.beginPath();
      ctx.arc(x, y, 4, 0, 2 * Math.PI);
      ctx.fillStyle = color;
      ctx.fill();
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = 1.5;
      ctx.stroke();
    };

    // Temperature dot
    if (stats.temperature_2m && stats.temperature_2m.median && this.panels.p1.valToY) {
      const v = stats.temperature_2m.median[this.hoverIdx];
      if (v != null) drawDot(this.panels.p1.valToY(v), "#dc2626");
    }

    // Wind speed dot
    if (stats.wind_speed_10m && stats.wind_speed_10m.median && this.panels.p4.valToY) {
      const v = stats.wind_speed_10m.median[this.hoverIdx];
      if (v != null) drawDot(this.panels.p4.valToY(v), "#334155");
    }

    // Pressure dot
    if (stats.pressure_msl && stats.pressure_msl.median && this.panels.p5.valToY) {
      const v = stats.pressure_msl.median[this.hoverIdx];
      if (v != null) drawDot(this.panels.p5.valToY(v), "#7c3aed");
    }

    ctx.restore();
  }

  _handlePointerMove(e) {
    if (!this.times || this.times.length === 0) return;

    const rect = this.canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;

    if (mouseX < this.marginLeft || mouseX > this.marginLeft + this.plotWidth) {
      this._handlePointerLeave();
      return;
    }

    const tHover = this._xToTime(mouseX);

    // Find nearest time index
    let bestIdx = 0;
    let minDiff = Infinity;
    for (let i = 0; i < this.times.length; i++) {
      const diff = Math.abs(this.times[i].getTime() - tHover);
      if (diff < minDiff) {
        minDiff = diff;
        bestIdx = i;
      }
    }

    this.hoverIdx = bestIdx;
    this.hoverPos = { x: mouseX, y: mouseY, clientX: e.clientX, clientY: e.clientY };

    this.render();
    this._updateHUD(bestIdx);
  }

  _handlePointerLeave() {
    if (this.hoverIdx !== null) {
      this.hoverIdx = null;
      this.hoverPos = null;
      this._showIdleHUD();
      this.render();
    }
  }

  _showIdleHUD() {
    if (!this.hud) return;
    const promptText = this.options.lang === "sk"
      ? "📍 Pohybujte myšou alebo ťahajte prstom po grafe pre zobrazenie hodinových hodnôt"
      : "📍 Hover or drag across chart to inspect hourly forecast values";
    this.hud.innerHTML = `
      <div class="hud-idle-prompt">
        <span>${promptText}</span>
      </div>
    `;
    this.hud.style.display = "flex";
  }

  _updateHUD(idx) {
    if (!this.hud || !this.times || !this.times[idx]) return;
    const dt = this.times[idx];
    const stats = this.data.stats;
    const t = METEO_TRANSLATIONS[this.options.lang] || METEO_TRANSLATIONS.en;
    const tz = this.options.tz;

    const dayName = t.days_full[tz === "utc" ? dt.getUTCDay() : dt.getDay()];
    const dateNum = tz === "utc" ? dt.getUTCDate() : dt.getDate();
    const monthNum = (tz === "utc" ? dt.getUTCMonth() : dt.getMonth()) + 1;
    const year = tz === "utc" ? dt.getUTCFullYear() : dt.getFullYear();
    const hour = String(tz === "utc" ? dt.getUTCHours() : dt.getHours()).padStart(2, "0");
    const min = String(tz === "utc" ? dt.getUTCMinutes() : dt.getMinutes()).padStart(2, "0");
    const tzBadge = tz === "utc" ? "UTC" : "Local";

    // Values
    const tMed = stats.temperature_2m?.median?.[idx];
    const tMin = stats.temperature_2m?.min?.[idx];
    const tMax = stats.temperature_2m?.max?.[idx];
    const tQ25 = stats.temperature_2m?.q25?.[idx];
    const tQ75 = stats.temperature_2m?.q75?.[idx];

    const pRain = stats.precipitation?.median?.[idx] || 0.0;
    const pSnow = stats.snowfall?.median?.[idx] || 0.0;
    const pMaxMember = stats.precipitation?.max?.[idx] || 0.0;

    const cTotal = stats.cloud_cover?.median?.[idx];
    const cHigh = stats.cloud_cover_high?.median?.[idx];
    const cMid = stats.cloud_cover_mid?.median?.[idx];
    const cLow = stats.cloud_cover_low?.median?.[idx];

    const wSpeed = stats.wind_speed_10m?.median?.[idx];
    const wSpeedKm = wSpeed != null ? (wSpeed * 3.6).toFixed(1) : "-";
    const wDir = stats.wind_direction_10m?.median?.[idx];
    const wCompass = wDir != null ? getCompassDir(wDir, this.options.lang) : "";

    const press = stats.pressure_msl?.median?.[idx];
    const sunAlt = this.sunAlts?.[idx];
    const moonAlt = this.moonAlts?.[idx];

    this.hud.innerHTML = `
      <div class="hud-content">
        <!-- Time & Ephemeris -->
        <div class="hud-col" style="min-width: 140px;">
          <div class="hud-time-title">
            <span>📅 ${dayName} ${dateNum}.${monthNum}. ${hour}:${min}</span>
            <span class="hud-badge">${tzBadge}</span>
          </div>
          <div class="hud-sub" style="display: flex; gap: 8px; margin-top: 2px;">
            <span class="hud-sun">☀ ${sunAlt != null ? `${sunAlt >= 0 ? "+" : ""}${sunAlt.toFixed(0)}°` : "-"}</span>
            <span class="hud-moon">☽ ${moonAlt != null ? `${moonAlt >= 0 ? "+" : ""}${moonAlt.toFixed(0)}°` : "-"}</span>
          </div>
        </div>

        <div class="hud-divider"></div>

        <!-- Temperature -->
        <div class="hud-col">
          <div class="hud-label">
            <span>🌡 ${t.temp.split("[")[0].trim()}</span>
            <span class="hud-val hud-val-temp">${tMed != null ? `${tMed.toFixed(1)} °C` : "-"}</span>
          </div>
          <div class="hud-sub">
            Q25–Q75: ${tQ25 != null ? tQ25.toFixed(1) : ""}-${tQ75 != null ? tQ75.toFixed(1) : ""}°C${tMin != null && tMax != null ? ` (${tMin.toFixed(0)}–${tMax.toFixed(0)}°)` : ""}
          </div>
        </div>

        <div class="hud-divider"></div>

        <!-- Precipitation -->
        <div class="hud-col">
          <div class="hud-label">
            <span>💧 ${t.precip.split("[")[0].trim()}</span>
            <span class="hud-val hud-val-precip">${pRain.toFixed(1)} mm</span>
          </div>
          <div class="hud-sub">
            Max: ${pMaxMember.toFixed(1)} mm ${pSnow > 0.05 ? `• ❄ ${pSnow.toFixed(1)} cm` : ""}
          </div>
        </div>

        <div class="hud-divider"></div>

        <!-- Clouds -->
        <div class="hud-col">
          <div class="hud-label">
            <span>☁ ${t.clouds.split("[")[0].trim()}</span>
            <span class="hud-val hud-val-clouds">${cTotal != null ? `${Math.round(cTotal)}%` : "-"}</span>
          </div>
          <div class="hud-sub">
            <span class="hud-cloud-h">H: ${cHigh != null ? `${Math.round(cHigh)}%` : "-"}</span> | 
            <span class="hud-cloud-m">M: ${cMid != null ? `${Math.round(cMid)}%` : "-"}</span> | 
            <span class="hud-cloud-l">L: ${cLow != null ? `${Math.round(cLow)}%` : "-"}</span>
          </div>
        </div>

        <div class="hud-divider"></div>

        <!-- Wind -->
        <div class="hud-col">
          <div class="hud-label">
            <span>💨 ${t.wind.split("[")[0].trim()}</span>
            <span class="hud-val hud-val-wind">${wSpeed != null ? `${wSpeed.toFixed(1)} m/s` : "-"}</span>
          </div>
          <div class="hud-sub">
            ${wSpeedKm} km/h • ${wCompass} (${wDir != null ? Math.round(wDir) : "-"}°)
          </div>
        </div>

        <div class="hud-divider"></div>

        <!-- Pressure -->
        <div class="hud-col">
          <div class="hud-label">
            <span>⏱ ${t.pressure.split("[")[0].trim()}</span>
            <span class="hud-val hud-val-press">${press != null ? `${press.toFixed(1)} hPa` : "-"}</span>
          </div>
          <div class="hud-sub">MSLP Sea Level</div>
        </div>
      </div>
    `;

    this.hud.style.display = "flex";
  }
}

// Global export
window.MeteogramChart = MeteogramChart;

/**
 * Universal Forecast Fetcher API
 * Tries local Python server first (/api/forecast).
 * If offline or running statically on GitHub Pages, falls back directly to Open-Meteo CORS APIs
 * with client-side ensemble percentile calculation.
 */
const PRESET_COORDS = {
  "bratislava-koliba": { name: "Bratislava - Koliba", country: "Slovakia", latitude: 48.1708, longitude: 17.1086, elevation: 287.0, timezone: "Europe/Bratislava" },
  "liptovsky mikulas": { name: "Liptovský Mikuláš", country: "Slovakia", latitude: 49.0833, longitude: 19.6167, elevation: 577.0, timezone: "Europe/Bratislava" },
  "jasna": { name: "Jasná (Demänovská Dolina)", country: "Slovakia", latitude: 48.9709, longitude: 19.5843, elevation: 1118.0, timezone: "Europe/Bratislava" },
  "jasná": { name: "Jasná (Demänovská Dolina)", country: "Slovakia", latitude: 48.9709, longitude: 19.5843, elevation: 1118.0, timezone: "Europe/Bratislava" },
  "plavecke podhradie": { name: "Plavecké Podhradie", country: "Slovakia", latitude: 48.4908, longitude: 17.2581, elevation: 230.0, timezone: "Europe/Bratislava" },
  "repiska": { name: "Repiská (Demänovská Dolina)", country: "Slovakia", latitude: 48.9905, longitude: 19.5759, elevation: 850.0, timezone: "Europe/Bratislava" },
  "repiská": { name: "Repiská (Demänovská Dolina)", country: "Slovakia", latitude: 48.9905, longitude: 19.5759, elevation: 850.0, timezone: "Europe/Bratislava" },
  "demanovska dolina": { name: "Demänovská Dolina - Repiská", country: "Slovakia", latitude: 48.9905, longitude: 19.5759, elevation: 850.0, timezone: "Europe/Bratislava" },
  "demänovská dolina": { name: "Demänovská Dolina - Repiská", country: "Slovakia", latitude: 48.9905, longitude: 19.5759, elevation: 850.0, timezone: "Europe/Bratislava" },
  "kosice": { name: "Košice", country: "Slovakia", latitude: 48.7164, longitude: 21.2611, elevation: 230.0, timezone: "Europe/Bratislava" },
  "poprad": { name: "Poprad", country: "Slovakia", latitude: 49.0594, longitude: 20.2978, elevation: 718.0, timezone: "Europe/Bratislava" },
  "vienna": { name: "Vienna", country: "Austria", latitude: 48.2082, longitude: 16.3738, elevation: 171.0, timezone: "Europe/Vienna" },
  "prague": { name: "Prague", country: "Czech Republic", latitude: 50.0755, longitude: 14.4378, elevation: 235.0, timezone: "Europe/Prague" }
};

window.MeteogramAPI = {
  async fetchForecast(locationQuery, days = 15, model = "aifs") {
    const cleanLoc = (locationQuery || "").toLowerCase().trim().replace(/[\s\/]+/g, "_");
    const cacheKey = `meteogram_fc_${cleanLoc}_${model}_${days}`;

    // 1. Try local server API first if running locally
    const isLocalhost = typeof window !== "undefined" && Boolean(
      window.location.hostname === "localhost" ||
      window.location.hostname === "127.0.0.1" ||
      window.location.hostname === "[::1]" ||
      window.location.port === "8080"
    );

    if (isLocalhost) {
      const localUrl = `/api/forecast?location=${encodeURIComponent(locationQuery)}&days=${days}&model=${model}&_t=${Date.now()}`;
      try {
        const resp = await fetch(localUrl);
        if (resp.ok) {
          const data = await resp.json();
          try { localStorage.setItem(cacheKey, JSON.stringify({ time: Date.now(), data })); } catch (e) {}
          return data;
        }
      } catch (e) {
        // Local server unavailable -> proceed to client-side Open-Meteo direct fetch
      }
    }

    // 2. Direct Open-Meteo fetch fallback (GitHub Pages / Standalone)
    try {
      const data = await this.fetchDirectOpenMeteo(locationQuery, days, model);
      if (data && data.stats) {
        try { localStorage.setItem(cacheKey, JSON.stringify({ time: Date.now(), data })); } catch (e) {}
        return data;
      }
    } catch (e) {
      console.warn("Direct Open-Meteo fetch failed:", e);
    }

    // 3. If offline / cellular unavailable: load cached model from localStorage!
    try {
      const cachedStr = localStorage.getItem(cacheKey);
      if (cachedStr) {
        const parsed = JSON.parse(cachedStr);
        if (parsed && parsed.data) {
          console.info("Using cached forecast from localStorage");
          parsed.data.isOfflineCached = true;
          return parsed.data;
        }
      }
    } catch (e) {}

    // 4. Try finding ANY cached forecast in localStorage for this location
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.startsWith(`meteogram_fc_${cleanLoc}_`)) {
          const item = JSON.parse(localStorage.getItem(k));
          if (item && item.data) {
            console.info("Using alternative cached forecast from localStorage:", k);
            item.data.isOfflineCached = true;
            return item.data;
          }
        }
      }
    } catch (e) {}

    throw new Error("No network connection and no cached forecast available.");
  },

  async geocode(query) {
    const norm = query.trim().toLowerCase();
    if (PRESET_COORDS[norm]) return PRESET_COORDS[norm];
    for (const [k, v] of Object.entries(PRESET_COORDS)) {
      if (norm.includes(k) || k.includes(norm)) return v;
    }

    // Check if lat,lon coordinates
    if (query.includes(",")) {
      const parts = query.split(",").map(p => parseFloat(p.trim()));
      if (!isNaN(parts[0]) && !isNaN(parts[1])) {
        return {
          name: `Coord (${parts[0].toFixed(2)}, ${parts[1].toFixed(2)})`,
          country: "",
          latitude: parts[0],
          longitude: parts[1],
          elevation: 0,
          timezone: "auto",
        };
      }
    }

    // Query Open-Meteo geocoding API
    try {
      const geoUrl = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(query)}&count=1&language=en&format=json`;
      const res = await fetch(geoUrl);
      if (res.ok) {
        const d = await res.json();
        if (d.results && d.results.length > 0) {
          const r = d.results[0];
          return {
            name: r.name,
            country: r.country || "",
            latitude: r.latitude,
            longitude: r.longitude,
            elevation: r.elevation || 0,
            timezone: r.timezone || "auto",
          };
        }
      }
    } catch (e) {}

    // Default fallback
    return PRESET_COORDS["bratislava-koliba"];
  },

  async fetchDirectOpenMeteo(locationQuery, days, model) {
    const loc = await this.geocode(locationQuery);
    const lat = loc.latitude;
    const lon = loc.longitude;

    // Model configuration
    let apiModel = "ecmwf_aifs025";
    let actualDays = Math.min(days, 15);
    let timeRes = "hourly";

    if (model === "icon_d2") {
      apiModel = "icon_d2";
      actualDays = Math.min(days, 3);
      timeRes = "hourly";
    } else if (model === "icon_eu") {
      apiModel = "icon_eu";
      actualDays = Math.min(days, 5);
      timeRes = "hourly";
    }

    const hourlyVars = [
      "temperature_2m",
      "precipitation",
      "snowfall",
      "cloud_cover",
      "cloud_cover_low",
      "cloud_cover_mid",
      "cloud_cover_high",
      "wind_speed_10m",
      "wind_direction_10m",
      "pressure_msl"
    ].join(",");

    const ensembleUrl = `https://ensemble-api.open-meteo.com/v1/ensemble?latitude=${lat}&longitude=${lon}&models=${apiModel}&hourly=${hourlyVars}&forecast_days=${actualDays}&timezone=UTC`;
    // For ICON-EU and ICON-D2, ensemble endpoint returns nulls for low/mid/high cloud layers.
    // Request cloud_cover_low, cloud_cover_mid, cloud_cover_high from deterministic forecast endpoint to backfill.
    const forecastEndpoint = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&models=${apiModel}&daily=sunrise,sunset,moonrise,moonset,moon_phase&hourly=cloud_cover_low,cloud_cover_mid,cloud_cover_high&forecast_days=${Math.min(actualDays + 2, 16)}&timezone=UTC`;

    const [ensRes, astroRes] = await Promise.all([
      fetch(ensembleUrl).then(r => r.json()).catch(() => null),
      fetch(forecastEndpoint).then(r => r.json()).catch(() => null),
    ]);

    if (!ensRes || !ensRes.hourly) {
      throw new Error("Failed to fetch weather data from Open-Meteo");
    }

    // Process ensemble members client-side
    const hourly = ensRes.hourly;

    // Backfill missing cloud layers from deterministic endpoint if ensemble layers are missing/null (ICON-EU & ICON-D2)
    if (astroRes && astroRes.hourly) {
      const cloudVars = ["cloud_cover_low", "cloud_cover_mid", "cloud_cover_high"];
      for (const cv of cloudVars) {
        const ensVals = hourly[cv];
        const hasValidEns = ensVals && Array.isArray(ensVals) && ensVals.some(v => v !== null && !isNaN(v));
        if (!hasValidEns && astroRes.hourly[cv]) {
          hourly[cv] = astroRes.hourly[cv];
        }
      }
    }
    const timeStrings = hourly.time || [];
    const stats = {
      times: timeStrings,
      elevation: ensRes.elevation || loc.elevation || 0,
      utc_offset_seconds: ensRes.utc_offset_seconds || 0,
    };

    const vars = [
      "temperature_2m", "precipitation", "snowfall",
      "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
      "wind_speed_10m", "wind_direction_10m", "pressure_msl"
    ];

    for (const v of vars) {
      const memberKeys = Object.keys(hourly).filter(k => k === v || k.startsWith(`${v}_member`));
      if (memberKeys.length === 0 || !hourly[memberKeys[0]]) {
        stats[v] = null;
        continue;
      }

      const numSteps = timeStrings.length;
      const med = new Array(numSteps);
      const q25 = new Array(numSteps);
      const q75 = new Array(numSteps);
      const minArr = new Array(numSteps);
      const maxArr = new Array(numSteps);

      for (let t = 0; t < numSteps; t++) {
        const vals = [];
        for (const mk of memberKeys) {
          const val = hourly[mk][t];
          if (val !== null && !isNaN(val)) vals.push(val);
        }

        if (vals.length === 0) {
          med[t] = null; q25[t] = null; q75[t] = null; minArr[t] = null; maxArr[t] = null;
          continue;
        }

        if (v === "wind_direction_10m") {
          let sSum = 0, cSum = 0;
          for (const d of vals) {
            const r = d * Math.PI / 180.0;
            sSum += Math.sin(r);
            cSum += Math.cos(r);
          }
          med[t] = Math.round((Math.atan2(sSum, cSum) * 180.0 / Math.PI + 360.0) % 360.0);
          vals.sort((a, b) => a - b);
          q25[t] = vals[Math.floor(vals.length * 0.25)];
          q75[t] = vals[Math.floor(vals.length * 0.75)];
          minArr[t] = vals[0];
          maxArr[t] = vals[vals.length - 1];
        } else {
          vals.sort((a, b) => a - b);
          med[t] = vals[Math.floor(vals.length * 0.5)];
          q25[t] = vals[Math.floor(vals.length * 0.25)];
          q75[t] = vals[Math.floor(vals.length * 0.75)];
          minArr[t] = vals[0];
          maxArr[t] = vals[vals.length - 1];
        }
      }

      stats[v] = {
        median: med,
        q25: q25,
        q75: q75,
        min: minArr,
        max: maxArr,
        members_count: memberKeys.length,
      };
    }

    // Process astronomy
    const astroDaily = {};
    const sunPairs = [];
    if (astroRes && astroRes.daily) {
      const d = astroRes.daily;
      const dTimes = d.time || [];
      const sRises = d.sunrise || [];
      const sSets = d.sunset || [];
      const mRises = d.moonrise || [];
      const mSets = d.moonset || [];
      const mPhases = d.moon_phase || [];

      for (let i = 0; i < dTimes.length; i++) {
        const dateKey = dTimes[i];
        if (sRises[i] && sSets[i]) {
          sunPairs.push([sRises[i], sSets[i]]);
        }
        const phase = mPhases[i] != null ? mPhases[i] : 0.0;
        const illum = Math.round((1.0 - Math.cos(2 * Math.PI * phase)) / 2.0 * 100.0);
        astroDaily[dateKey] = {
          sunrise: sRises[i],
          sunset: sSets[i],
          moonrise: mRises[i],
          moonset: mSets[i],
          moon_phase: phase,
          illum_pct: illum,
        };
      }
    }

    return {
      location: loc,
      model: model,
      model_fallback: false,
      fallback_from: "",
      stats: stats,
      astro: {
        sun_pairs: sunPairs,
        daily: astroDaily,
      }
    };
  }
};

