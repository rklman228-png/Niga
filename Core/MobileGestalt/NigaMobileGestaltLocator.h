#ifndef NIGA_MOBILEGESTALT_LOCATOR_H
#define NIGA_MOBILEGESTALT_LOCATOR_H

#import <Foundation/Foundation.h>
#include <stddef.h>

/// Returns the byte offset inside MobileGestalt CacheData for the hashed key,
/// or 0 when no safe candidate can be resolved.
size_t niga_mg_cache_data_offset(const char *key, size_t cache_data_length);

/// Human-readable diagnostics from the most recent locator call.
char *niga_mg_copy_locator_diagnostics(void);
void niga_mg_free_locator_string(char *value);

#endif
