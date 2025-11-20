//
//  KalmanFilter3D.cpp
//  PoseA
//
//  Created by Ardhika Maulidani on 7/7/25.
//

#include "KalmanFilter3D.hpp"
#include <cstring> // for memset
#include <cmath>

struct KalmanFilter3D {
    double x[6];      // [x, vx, y, vy, z, vz]
    double P[6][6];   // Covariance matrix
    double A[6][6];   // State transition
    double H[3][6];   // Measurement model
    double Q[6][6];   // Process noise
    double R[3][3];   // Measurement noise
};

KalmanFilter3D* kalman3d_create(double dt) {
    KalmanFilter3D* kf = new KalmanFilter3D;

    // State transition A
    memset(kf->A, 0, sizeof(kf->A));
    for (int i = 0; i < 6; i++) kf->A[i][i] = 1.0f;
    kf->A[0][1] = dt;
    kf->A[2][3] = dt;
    kf->A[4][5] = dt;

    // Measurement matrix H
    memset(kf->H, 0, sizeof(kf->H));
    kf->H[0][0] = 1.0f; // x
    kf->H[1][2] = 1.0f; // y
    kf->H[2][4] = 1.0f; // z

    // Process noise Q
    memset(kf->Q, 0, sizeof(kf->Q));
    kf->Q[0][0] = 0.05f;
    kf->Q[1][1] = 0.1f;
    kf->Q[2][2] = 0.05f;
    kf->Q[3][3] = 0.1f;
    kf->Q[4][4] = 0.05f;
    kf->Q[5][5] = 0.1f;

    // Measurement noise R
    memset(kf->R, 0, sizeof(kf->R));
    kf->R[0][0] = 5.0f;
    kf->R[1][1] = 5.0f;
    kf->R[2][2] = 5.0f;

    kalman3d_reset(kf, 0, 0, 0);
    return kf;
}

void kalman3d_reset(KalmanFilter3D* kf, double x, double y, double z) {
    memset(kf->x, 0, sizeof(kf->x));
    kf->x[0] = x;
    kf->x[2] = y;
    kf->x[4] = z;

    memset(kf->P, 0, sizeof(kf->P));
    for (int i = 0; i < 6; ++i) {
        kf->P[i][i] = 1.0f;
    }
}

void kalman3d_update(KalmanFilter3D* kf, double* mx, double* my, double* mz) {
    // === Predict ===
    double xp[6] = {0};
    for (int i = 0; i < 6; i++)
        for (int j = 0; j < 6; j++)
            xp[i] += kf->A[i][j] * kf->x[j];

    double Pp[6][6] = {0};
    for (int i = 0; i < 6; ++i)
        for (int j = 0; j < 6; ++j)
            for (int k = 0; k < 6; ++k)
                Pp[i][j] += kf->A[i][k] * kf->P[k][j];
    for (int i = 0; i < 6; ++i)
        for (int j = 0; j < 6; ++j)
            kf->P[i][j] = Pp[i][j] + kf->Q[i][j];

    // === Update ===
    if (mx && my && mz) {
        double z[3] = {*mx, *my, *mz};

        double y[3] = {0}; // innovation
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 6; j++)
                y[i] += kf->H[i][j] * xp[j];
        for (int i = 0; i < 3; i++)
            y[i] = z[i] - y[i];

        // Innovation covariance S = HPHᵀ + R
        double S[3][3] = {0};
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                for (int k = 0; k < 6; ++k)
                    for (int l = 0; l < 6; ++l)
                        S[i][j] += kf->H[i][k] * kf->P[k][l] * kf->H[j][l];
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                S[i][j] += kf->R[i][j];

        // Kalman Gain K = P Hᵀ S⁻¹
        // Note: For simplicity, assume S is diagonal here
        double K[6][3] = {0};
        for (int i = 0; i < 6; ++i)
            for (int j = 0; j < 3; ++j)
                for (int k = 0; k < 6; ++k)
                    K[i][j] += kf->P[i][k] * kf->H[j][k];
        for (int i = 0; i < 6; ++i)
            for (int j = 0; j < 3; ++j)
                K[i][j] /= S[j][j]; // S assumed diagonal

        // Update state
        for (int i = 0; i < 6; ++i)
            for (int j = 0; j < 3; ++j)
                xp[i] += K[i][j] * y[j];

        // Update covariance P = (I - K * H) * P
        double KH[6][6] = {0};
        for (int i = 0; i < 6; ++i)
            for (int j = 0; j < 6; ++j)
                for (int k = 0; k < 3; ++k)
                    KH[i][j] += K[i][k] * kf->H[k][j];
        for (int i = 0; i < 6; ++i)
            for (int j = 0; j < 6; ++j)
                kf->P[i][j] = (i == j ? 1.0f : 0.0f) - KH[i][j];

        // Store new state
        for (int i = 0; i < 6; i++)
            kf->x[i] = xp[i];
    } else {
        // No update — just prediction
        for (int i = 0; i < 6; i++)
            kf->x[i] = xp[i];
    }
}

void kalman3d_get_state(KalmanFilter3D* kf, double* x, double* y, double* z) {
    if (kf && x && y && z) {
        *x = kf->x[0]; // x
        *y = kf->x[2]; // y
        *z = kf->x[4]; // z
    }
}

void kalman3d_free(KalmanFilter3D* kf) {
    delete kf;
}
