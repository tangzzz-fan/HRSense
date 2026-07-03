#include "hrs_compute.h"
#include <cmath>
#include <algorithm>
#include <cstring>
#include <vector>

// ============ Internal helpers ============

static double mean(const uint16_t *rr, size_t n) {
    double s = 0.0;
    for (size_t i = 0; i < n; ++i) s += rr[i];
    return s / n;
}

static double mean_double(const double *values, size_t n) {
    if (!values || n == 0) return 0.0;
    double sum = 0.0;
    for (size_t i = 0; i < n; ++i) sum += values[i];
    return sum / static_cast<double>(n);
}

static void diff(const uint16_t *rr, size_t n, std::vector<double> &out) {
    out.clear();
    out.reserve(n > 1 ? n - 1 : 0);
    for (size_t i = 1; i < n; ++i) {
        out.push_back((double)rr[i] - (double)rr[i-1]);
    }
}

// ============ Sleep feature helpers ============

static double compute_linear_slope(const double *values, size_t n) {
    if (!values || n < 2) return 0.0;

    double sum_x = 0.0;
    double sum_y = 0.0;
    double sum_xy = 0.0;
    double sum_xx = 0.0;

    for (size_t i = 0; i < n; ++i) {
        double x = static_cast<double>(i);
        double y = values[i];
        sum_x += x;
        sum_y += y;
        sum_xy += x * y;
        sum_xx += x * x;
    }

    double denom = static_cast<double>(n) * sum_xx - sum_x * sum_x;
    if (std::abs(denom) < 1e-12) return 0.0;
    return (static_cast<double>(n) * sum_xy - sum_x * sum_y) / denom;
}

static double compute_normalized_range(const double *values, size_t n) {
    if (!values || n < 2) return 0.0;

    double min_value = values[0];
    double max_value = values[0];
    for (size_t i = 1; i < n; ++i) {
        min_value = std::min(min_value, values[i]);
        max_value = std::max(max_value, values[i]);
    }

    double baseline = std::abs(mean_double(values, n));
    if (baseline < 1e-6) return 0.0;
    return (max_value - min_value) / baseline;
}

// ============ Time-domain HRV ============

static double compute_sdnn(const uint16_t *rr, size_t n, double mn) {
    double sum = 0.0;
    for (size_t i = 0; i < n; ++i) {
        double d = rr[i] - mn;
        sum += d * d;
    }
    return std::sqrt(sum / (n - 1));
}

static double compute_rmssd(const std::vector<double> &diffs) {
    if (diffs.empty()) return 0.0;
    double sum = 0.0;
    for (double d : diffs) sum += d * d;
    return std::sqrt(sum / diffs.size());
}

static double compute_pnn50(const std::vector<double> &diffs) {
    if (diffs.empty()) return 0.0;
    size_t count = 0;
    for (double d : diffs) {
        if (std::abs(d) > 50.0) ++count;
    }
    return 100.0 * count / diffs.size();
}

// ============ Poincaré (SD1/SD2) ============

static void compute_sd1_sd2(const std::vector<double> &diffs, double &sd1, double &sd2) {
    if (diffs.empty()) { sd1 = 0; sd2 = 0; return; }
    // SD1 = RMS of successive-difference / sqrt(2)
    // x_i = rr[i], x_{i+1} = rr[i+1]
    // rotated 45°: (x_i + x_{i+1})/√2, (x_i - x_{i+1})/√2
    // SD1 = std of (x_i - x_{i+1})/√2 = rmssd / √2
    // But SD1 from Poincaré is properly computed from perpendicular distances.
    // Simple approximation: SDSD = std of successive differences.
    // SD1 = SDSD / sqrt(2)
    double sum = 0, sumsq = 0;
    size_t n = diffs.size();
    for (double d : diffs) { sum += d; sumsq += d * d; }
    double var = (sumsq - sum * sum / n) / n;
    double sdsd = std::sqrt(var);
    sd1 = sdsd / std::sqrt(2.0);
    // SD2 = sqrt(2 * SDNN² - SD1²)
    // Actually SD2 = sqrt(2 * SDSD² - SD1²) ... no.
    // Standard formula: SD2 = sqrt(2 * SDNN² - SD1²)
    // We don't have SDNN here, so use a simpler proxy.
    sd2 = sd1 * 1.8;  // placeholder approximation
}

// ============ Frequency domain (Lomb-Scargle simplified) ============

struct FreqBand {
    double low;
    double high;
    double power;
};

static FreqBand freq_bands[2] = {
    {0.04, 0.15, 0.0},   // LF
    {0.15, 0.40, 0.0},   // HF
};

// Simplified Lomb-Scargle periodogram: for each frequency f,
//   P(f) = (sum(rr_i * cos(2πf·t_i))² + sum(rr_i * sin(2πf·t_i))²) / (2 * σ² * N)
// We use a fast approximation with 512 frequency bins.
static void compute_frequency_power(const uint16_t *rr, size_t n,
                                     double &lf, double &hf, double &total) {
    if (n < 4) { lf = 0; hf = 0; total = 0; return; }

    // Build time array (cumulative RR in seconds)
    std::vector<double> t_secs(n);
    t_secs[0] = 0;
    for (size_t i = 1; i < n; ++i) {
        t_secs[i] = t_secs[i-1] + rr[i] / 1000.0;
    }
    double total_time = t_secs[n-1];

    // Minimum resolvable frequency
    double f_min = 1.0 / total_time;
    double f_max = 0.5;  // Nyquist relative to mean HR ~70 bpm → 1.17 Hz → 0.4 Hz is conservative
    int bins = 256;
    double df = (f_max - f_min) / bins;

    double mn = mean(rr, n);
    double variance = 0;
    for (size_t i = 0; i < n; ++i) {
        double d = rr[i] - mn;
        variance += d * d;
    }
    variance /= n;

    lf = hf = total = 0;
    double denom = 2.0 * variance * n;
    if (denom < 1e-10) return;

    for (int b = 0; b < bins; ++b) {
        double f = f_min + b * df;
        double sum_cos = 0, sum_sin = 0;
        for (size_t i = 0; i < n; ++i) {
            double phase = 2.0 * M_PI * f * t_secs[i];
            double x = rr[i] - mn;
            sum_cos += x * std::cos(phase);
            sum_sin += x * std::sin(phase);
        }
        double power = (sum_cos * sum_cos + sum_sin * sum_sin) / denom;
        total += power * df;

        if (f >= 0.04 && f <= 0.15) lf += power * df;
        if (f >= 0.15 && f <= 0.40) hf += power * df;
    }
}

// ============ Sample Entropy ============

static double compute_sample_entropy(const std::vector<double> &x, int m, double r) {
    size_t N = x.size();
    if (N < (size_t)m + 1) return 0;

    auto count_matches = [&](int embed) -> size_t {
        size_t count = 0;
        for (size_t i = 0; i < N - embed; ++i) {
            for (size_t j = i + 1; j < N - embed; ++j) {
                double max_dist = 0;
                for (int k = 0; k < embed; ++k) {
                    double dist = std::abs(x[i + k] - x[j + k]);
                    if (dist > max_dist) max_dist = dist;
                }
                if (max_dist < r) ++count;
            }
        }
        return count;
    };

    size_t A = count_matches(m + 1);
    size_t B = count_matches(m);
    if (B == 0) return 0;
    return -std::log((double)A / (double)B);
}

// ============ DFA alpha1 ============

static double compute_dfa_alpha1(const uint16_t *rr, size_t n) {
    // Simplified DFA: only short-range scales 4-16 beats
    if (n < 20) return 0;
    double mn = mean(rr, n);
    std::vector<double> integrated(n);
    integrated[0] = rr[0] - mn;
    for (size_t i = 1; i < n; ++i) {
        integrated[i] = integrated[i-1] + (rr[i] - mn);
    }

    double sum_logn_logn = 0, sum_logn_logF = 0;
    int scales_tested = 0;
    for (int scale = 4; scale <= 16 && scale * 4 < (int)n; scale *= 2) {
        int windows = (int)n / scale;
        if (windows < 2) continue;
        double sum_F = 0;
        for (int w = 0; w < windows; ++w) {
            double sx = 0, sy = 0, sxx = 0, sxy = 0;
            int start = w * scale;
            for (int k = 0; k < scale; ++k) {
                double x = k;
                double y = integrated[start + k];
                sx += x; sy += y;
                sxx += x * x; sxy += x * y;
            }
            double denom = scale * sxx - sx * sx;
            double a = (denom != 0) ? (scale * sxy - sx * sy) / denom : 0;
            for (int k = 0; k < scale; ++k) {
                double residual = integrated[start + k] - (a * k + sy / scale);
                sum_F += residual * residual;
            }
        }
        double F = std::sqrt(sum_F / (windows * scale));
        if (F > 0) {
            sum_logn_logn += 1;
            sum_logn_logF += std::log(F) / std::log(2.0);
            ++scales_tested;
        }
    }
    if (scales_tested < 2) return 0;
    // Simple slope
    // α = mean(log2(F_n)) / mean(log2(n))
    // For n=4..16: log2(n) ranges from 2 to 4.
    // Simplified: α = total logF / (2 + 3 + 4 = 9) for 3 scales.
    return sum_logn_logF / sum_logn_logn;
}

// ============ Stress Index (Baevsky) ============

static double compute_stress_index(const uint16_t *rr, size_t n, double mode_rr, double sdnn_val) {
    if (n < 2 || sdnn_val < 1e-10) return 0;
    // Build histogram to find mode
    uint16_t min_rr = rr[0], max_rr = rr[0];
    for (size_t i = 0; i < n; ++i) {
        if (rr[i] < min_rr) min_rr = rr[i];
        if (rr[i] > max_rr) max_rr = rr[i];
    }
    // AMo = percentage of RR = mode_RR ± 50ms
    double amo_count = 0;
    for (size_t i = 0; i < n; ++i) {
        if (std::abs((double)rr[i] - mode_rr) <= 50) ++amo_count;
    }
    double amo = amo_count / n * 100.0;
    double range_rr = max_rr - min_rr; // MxDMn
    if (range_rr < 1) return 0;
    return amo / (2.0 * range_rr / 1000.0 * sdnn_val / 1000.0); // simplified SI
}

// ============ Public API ============

int hrs_compute_init(void) { return 0; }
void hrs_compute_deinit(void) {}

int hrs_compute_hrv(const uint16_t *rr_ms, size_t count, hrs_hrv_metrics_t *out) {
    if (!rr_ms || !out || count < 2) return -1;

    std::memset(out, 0, sizeof(*out));

    double mn = mean(rr_ms, count);
    out->mean_rr = mn;
    out->hr = 60000.0 / mn;

    out->sdnn = compute_sdnn(rr_ms, count, mn);

    std::vector<double> diffs;
    diff(rr_ms, count, diffs);
    if (!diffs.empty()) {
        out->rmssd = compute_rmssd(diffs);
        out->pnn50 = compute_pnn50(diffs);
        compute_sd1_sd2(diffs, out->sd1, out->sd2);
    }

    // SD2 from known formula: SD2 = sqrt(2 * SDNN² - SD1²)
    // Recalculate properly
    double sd1 = out->sd1;
    double sdnn = out->sdnn;
    out->sd2 = std::sqrt(std::max(0.0, 2.0 * sdnn * sdnn - sd1 * sd1));

    double lf, hf, total;
    compute_frequency_power(rr_ms, count, lf, hf, total);
    out->lf_power = lf;
    out->hf_power = hf;
    out->total_power = total;
    out->lf_hf_ratio = (hf > 1e-10) ? lf / hf : 0;

    // Sample entropy on RR intervals (not diffs)
    std::vector<double> rr_doubles(count);
    for (size_t i = 0; i < count; ++i) rr_doubles[i] = rr_ms[i];
    double sdnn_val = out->sdnn;
    out->sample_entropy = compute_sample_entropy(rr_doubles, 2, 0.2 * sdnn_val);

    out->dfa_alpha1 = compute_dfa_alpha1(rr_ms, count);

    // Find mode (most common RR rounded to nearest 50ms)
    uint16_t mode_rr = (uint16_t)(mn / 50.0 + 0.5) * 50;
    out->stress_index = compute_stress_index(rr_ms, count, mode_rr, sdnn_val);

    return 0;
}

int hrs_extract_features(const hrs_hrv_metrics_t *metrics, float *out_features) {
    if (!metrics || !out_features) return -1;
    out_features[0]  = (float)metrics->sdnn;
    out_features[1]  = (float)metrics->rmssd;
    out_features[2]  = (float)metrics->pnn50;
    out_features[3]  = (float)metrics->mean_rr;
    out_features[4]  = (float)metrics->hr;
    out_features[5]  = (float)metrics->lf_power;
    out_features[6]  = (float)metrics->hf_power;
    out_features[7]  = (float)metrics->lf_hf_ratio;
    out_features[8]  = (float)metrics->total_power;
    out_features[9]  = (float)metrics->sd1;
    out_features[10] = (float)metrics->sd2;
    out_features[11] = (float)metrics->sample_entropy;
    out_features[12] = (float)metrics->dfa_alpha1;
    out_features[13] = (float)metrics->stress_index;
    return 0;
}

int hrs_compute_hr_trend(const double *hr_values, size_t count, double *out_trend) {
    if (!out_trend) return -1;
    *out_trend = compute_linear_slope(hr_values, count);
    return 0;
}

int hrs_compute_circadian_variation(const double *hrv_values, size_t count, double *out_variation) {
    if (!out_variation) return -1;
    *out_variation = compute_normalized_range(hrv_values, count);
    return 0;
}
