#pragma once
#include <android/sensor.h>
#include <android_native_app_glue.h>

#ifdef __cplusplus
extern "C" {
#endif

void call_source_process(struct android_app *state,
                         struct android_poll_source *s);
const float *get_acceleration(const ASensorEvent *event);

#ifdef __cplusplus
}
#endif
