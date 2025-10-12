#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Create a platform plugin for the platform specified at compile time.
struct IPlatformPlugin* PlatformPlugin_create(const struct Options* options, const struct PlatformData* data);
void PlatformPlugin_updateOptions(struct IPlatformPlugin* self, const struct Options* options);

#ifdef __cplusplus
}
#endif
