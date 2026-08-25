#ifndef NIGA_SCENE_PROBE_H
#define NIGA_SCENE_PROBE_H

#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

char *niga_scene_probe_json(const char *bundle_id);
void niga_scene_probe_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
