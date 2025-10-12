#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Create a graphics plugin for the graphics API specified in the options.
struct IGraphicsPlugin* GraphicsPlugin_create(const struct Options* options, struct IPlatformPlugin* platformPlugin);
void GraphicsPlugin_updateOptions(struct IGraphicsPlugin* self, const struct Options* options);

#ifdef __cplusplus
}
#endif
