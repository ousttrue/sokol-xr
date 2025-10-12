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
void renderView(void *p, void *texture, int64_t format, int width, int height, const float m[16], const void *pCube,
                size_t len);

#ifdef __cplusplus
}
#endif
