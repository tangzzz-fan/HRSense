#ifndef HRS_COMPUTE_H
#define HRS_COMPUTE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// HRV metrics — 14 fields (must match Swift HRVMetrics.toFeatureVector() order).
typedef struct {
    double sdnn;              // 0
    double rmssd;             // 1
    double pnn50;             // 2
    double mean_rr;           // 3
    double hr;                // 4
    double lf_power;          // 5
    double hf_power;          // 6
    double lf_hf_ratio;       // 7
    double total_power;       // 8
    double sd1;               // 9
    double sd2;               // 10
    double sample_entropy;    // 11
    double dfa_alpha1;        // 12
    double stress_index;      // 13
} hrs_hrv_metrics_t;

#define HRS_FEATURE_DIM 14

/// Initialise compute subsystem (allocate FFT plans, etc.).
int hrs_compute_init(void);

/// Deinitialise compute subsystem.
void hrs_compute_deinit(void);

/// Compute HRV metrics from an array of RR intervals (milliseconds).
///
/// @param rr_ms       Pointer to array of uint16 RR intervals (ms).
/// @param count       Number of RR intervals.
/// @param out_metrics Pointer to caller-allocated hrs_hrv_metrics_t.
/// @return 0 on success, non-zero on error (e.g. too few intervals).
int hrs_compute_hrv(const uint16_t *rr_ms, size_t count, hrs_hrv_metrics_t *out_metrics);

/// Extract a 14-element feature vector from HRV metrics.
///
/// @param metrics     Pointer to populated hrs_hrv_metrics_t.
/// @param out_features Pointer to caller-allocated float[HRS_FEATURE_DIM].
/// @return 0 on success.
int hrs_extract_features(const hrs_hrv_metrics_t *metrics, float *out_features);

#ifdef __cplusplus
}
#endif

#endif /* HRS_COMPUTE_H */
