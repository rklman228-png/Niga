#ifndef NIGA_SANDBOX_H
#define NIGA_SANDBOX_H
#include <stdint.h>
#include <stdbool.h>

int64_t niga_escape_path(const char *path, bool create);
void niga_release_path(int64_t handle);

// Metadata-only ContainerManager lookup. Returns a malloc-owned absolute path
// for a concrete MCM container (for example class 12 com.apple.springboard),
// or NULL when the lookup is unavailable/denied. Free with niga_free_string.
char *niga_mcm_container_path(uint64_t container_class,
                              const char *identifier,
                              bool group_identifier);

char *niga_list_children(const char *path, int64_t max_inode);
void niga_free_string(char *value);

#endif
