#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void *create();
void destroy(void *p);
int initializeDevice(void *p, void *instance, uint64_t systemId);
int64_t selectColorSwapchainFormat(void *p, int64_t *formats, size_t len);
const void *getGraphicsBinding(void *p);
void allocateSwapchainImageStructs(void *p, void *pImage, size_t len);
void renderView(void *p, const void *view, const void *image, int64_t format, const void *pCube, size_t len);

#ifdef __cplusplus
}
#endif
