//
//  KalmanFilter1D.hpp
//  PoseA
//
//  Created by Ardhika Maulidani on 7/7/25.
//

#ifndef KalmanFilter1D_hpp
#define KalmanFilter1D_hpp

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KalmanFilter1D KalmanFilter1D;

KalmanFilter1D* kalman_create(double dt);
void kalman_reset(KalmanFilter1D* filter, double angle);
double kalman_update(KalmanFilter1D* filter, double* measurement);
void kalman_free(KalmanFilter1D* filter);

#ifdef __cplusplus
}
#endif

#endif /* KalmanFilter1D_hpp */
