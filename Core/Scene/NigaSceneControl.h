#ifndef NIGA_SCENE_CONTROL_H
#define NIGA_SCENE_CONTROL_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

char *niga_scene_apply_profile(const char *bundle_id,
                               double x,
                               double y,
                               double width,
                               double height,
                               int orientation,
                               bool always_on_top);
void niga_scene_control_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
