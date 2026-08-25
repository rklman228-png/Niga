#ifndef NIGA_SANDBOX_H
#define NIGA_SANDBOX_H
#include <stdint.h>
#include <stdbool.h>
int64_t niga_escape_path(const char *path, bool create);
void niga_release_path(int64_t handle);
char *niga_list_children(const char *path, int64_t max_inode);
void niga_free_string(char *value);
#endif
