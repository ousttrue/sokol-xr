#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void *create();
void destroy(void *p);
int initializeDevice(void *p, void *instance, uint64_t systemId);
const void *getGraphicsBinding(void *p);
void allocateSwapchainImageStructs(void *p, void *pImage, size_t len);
void renderView(void *p, uintptr_t texture, int64_t format, int width, int height, const float fov[4], const float view_position[3],
                const float view_rotation[4], const void *pCube, size_t len);

#ifdef __cplusplus
}
#endif
