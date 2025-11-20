//
//  KalmanFilter1D.cpp
//  PoseA
//
//  Created by Ardhika Maulidani on 7/7/25.
//

#include "KalmanFilter1D.hpp"
#include <cmath>

struct KalmanFilter1D {
    double x[2];     // [angle, velocity]
    double P[2][2];  // Covariance matrix
    double A[2][2];  // State transition
    double H[2];     // Measurement model
    double Q[2][2];  // Process noise
    double R;        // Measurement noise
};

KalmanFilter1D* kalman_create(double dt) {
    KalmanFilter1D* kf = new KalmanFilter1D;

    kf->A[0][0] = 1.0f; kf->A[0][1] = dt;
    kf->A[1][0] = 0.0f; kf->A[1][1] = 1.0f;

    kf->H[0] = 1.0f; kf->H[1] = 0.0f;

    kf->Q[0][0] = 0.01f; kf->Q[0][1] = 0.0f;
    kf->Q[1][0] = 0.0f;  kf->Q[1][1] = 0.1f;

    kf->R = 5.0f;

    kalman_reset(kf, 0.0f);
    return kf;
}

void kalman_reset(KalmanFilter1D* kf, double angle) {
    kf->x[0] = angle;
    kf->x[1] = 0.0f;

    kf->P[0][0] = 1.0f; kf->P[0][1] = 0.0f;
    kf->P[1][0] = 0.0f; kf->P[1][1] = 1.0f;
}

double kalman_update(KalmanFilter1D* kf, double* measurement) {
    // Predict
    double x_pred[2] = {
        kf->A[0][0] * kf->x[0] + kf->A[0][1] * kf->x[1],
        kf->A[1][0] * kf->x[0] + kf->A[1][1] * kf->x[1]
    };

    double P_pred[2][2];
    for (int i = 0; i < 2; ++i)
        for (int j = 0; j < 2; ++j)
            P_pred[i][j] = kf->Q[i][j] +
                kf->A[i][0] * kf->P[0][j] +
                kf->A[i][1] * kf->P[1][j];

    if (measurement) {
        double z = *measurement;
        double y = z - (kf->H[0] * x_pred[0] + kf->H[1] * x_pred[1]); // innovation

        double S = kf->H[0] * (P_pred[0][0] * kf->H[0] + P_pred[0][1] * kf->H[1]) +
                  kf->H[1] * (P_pred[1][0] * kf->H[0] + P_pred[1][1] * kf->H[1]) + kf->R;

        double K[2];
        K[0] = (P_pred[0][0] * kf->H[0] + P_pred[0][1] * kf->H[1]) / S;
        K[1] = (P_pred[1][0] * kf->H[0] + P_pred[1][1] * kf->H[1]) / S;

        // Update state
        kf->x[0] = x_pred[0] + K[0] * y;
        kf->x[1] = x_pred[1] + K[1] * y;

        // Update covariance
        double KH[2][2] = {
            { K[0] * kf->H[0], K[0] * kf->H[1] },
            { K[1] * kf->H[0], K[1] * kf->H[1] }
        };

        for (int i = 0; i < 2; ++i)
            for (int j = 0; j < 2; ++j)
                kf->P[i][j] = (i == j ? 1.0f : 0.0f) - KH[i][j];

        // Optional: apply new covariance to P_pred
        // Not applied here to keep it minimal
    } else {
        kf->x[0] = x_pred[0];
        kf->x[1] = x_pred[1];
        kf->P[0][0] = P_pred[0][0];
        kf->P[0][1] = P_pred[0][1];
        kf->P[1][0] = P_pred[1][0];
        kf->P[1][1] = P_pred[1][1];
    }

    return kf->x[0]; // return filtered angle
}

void kalman_free(KalmanFilter1D* kf) {
    delete kf;
}
