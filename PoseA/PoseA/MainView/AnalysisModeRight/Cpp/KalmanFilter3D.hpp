//
//  KalmanFilter3D.hpp
//  PoseA
//
//  Created by Ardhika Maulidani on 7/7/25.
//

#ifndef KalmanFilter3D_hpp
#define KalmanFilter3D_hpp

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KalmanFilter3D KalmanFilter3D;

KalmanFilter3D* kalman3d_create(double dt);
void kalman3d_reset(KalmanFilter3D* filter, double x, double y, double z);
void kalman3d_update(KalmanFilter3D* filter, double* x, double* y, double* z);
void kalman3d_free(KalmanFilter3D* filter);
void kalman3d_get_state(KalmanFilter3D* filter, double* x, double* y, double* z);

#ifdef __cplusplus
}
#endif

#endif /* KalmanFilter3D_hpp */
